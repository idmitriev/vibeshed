import Foundation

/// Builds the ffmpeg command line that cuts one output from a take.
public enum FFmpegPlan {
    public static func arguments(
        for output: OutputSpec,
        manifest: Manifest,
        input: String,
        destination: String
    ) throws -> [String] {
        var args = ["-hide_banner", "-loglevel", "error", "-y", "-i", input]
        args += try ["-filter_complex", filterGraph(for: output, manifest: manifest), "-map", "[out]"]
        args += encoderArguments(for: output)
        args.append(destination)
        return args
    }

    /// The crop in source pixels, rounded to even numbers for yuv420p.
    public static func cropPixels(for output: OutputSpec, manifest: Manifest) throws -> Rect {
        let bounds = manifest.display.bounds
        var rect = bounds
        if case let .region(region) = output.crop {
            switch region {
            case let .rect(fixed):
                rect = fixed
            case let .window(target):
                guard let seen = manifest.windows[target.name] else {
                    throw SceneError.invalid(
                        "output '\(output.name)' crops to '\(target.name)', which never appeared on screen"
                    )
                }
                rect = seen
            }
        }
        rect = rect.insetBy(-output.padding).clamped(to: bounds)
        guard rect.width > 0, rect.height > 0 else {
            throw SceneError.invalid("output '\(output.name)' crops outside the display")
        }
        let scale = manifest.display.scale
        func even(_ value: Double) -> Double { (value * scale / 2).rounded(.down) * 2 }
        return Rect(x: even(rect.x), y: even(rect.y), width: even(rect.width), height: even(rect.height))
    }

    static func filterGraph(for output: OutputSpec, manifest: Manifest) throws -> String {
        let crop = try cropPixels(for: output, manifest: manifest)
        var chain = try [trim(for: output, manifest: manifest)]
        chain.append("crop=\(int(crop.width)):\(int(crop.height)):\(int(crop.x)):\(int(crop.y))")
        if output.speed != 1 {
            chain.append("setpts=PTS/\(output.speed)")
        }
        if output.format.isVideo {
            let fps = output.fps ?? (output.format == .gif ? 15 : 60)
            chain.append("fps=\(fps)")
            let cuts = try skippedRanges(for: output, manifest: manifest)
            if !cuts.isEmpty {
                // Quoted, so the commas inside stay part of the expression.
                let between = cuts.map { "between(t,\(seconds($0.lowerBound)),\(seconds($0.upperBound)))" }
                chain.append("select='not(\(between.joined(separator: "+")))',setpts=N/(\(fps)*TB)")
            }
        }
        var graph = "[0:v]\(chain.joined(separator: ","))[clip];"
        var clip = "clip"
        if let loop = output.loop, output.format.isVideo {
            graph += try loopGraph(for: output, manifest: manifest, crossfade: loop, input: clip, output: "looped")
            clip = "looped"
        }
        graph += fitGraph(for: output, input: clip, output: output.format == .gif ? "fitted" : "out")
        if output.format == .gif {
            graph += ";[fitted]split[a][b];[a]palettegen=stats_mode=diff[palette];"
            graph += "[b][palette]paletteuse=dither=bayer:bayer_scale=3[out]"
        }
        return graph
    }

    /// Crossfades the clip's last `crossfade` seconds into its first ones and
    /// starts the output that far in, so its last frame leads straight back
    /// to its first: `<video loop>` cycles without a visible seam, even when
    /// the take ends in a slightly different state than it starts.
    private static func loopGraph(
        for output: OutputSpec,
        manifest: Manifest,
        crossfade: Double,
        input: String,
        output label: String
    ) throws -> String {
        let start = try output.from.map(manifest.resolve) ?? 0
        let end = try output.to.map(manifest.resolve) ?? manifest.duration ?? 0
        let skipped = try skippedRanges(for: output, manifest: manifest)
            .reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        let length = (end - start) / output.speed - skipped
        guard crossfade > 0, length > 3 * crossfade else {
            throw SceneError.invalid(
                "output '\(output.name)': a \(crossfade)s loop needs a clip over \(3 * crossfade)s"
            )
        }
        let fade = seconds(crossfade)
        return "[\(input)]split[body][head];"
            + "[head]trim=end=\(fade),setpts=PTS-STARTPTS,settb=AVTB[headpart];"
            + "[body]trim=start=\(fade),setpts=PTS-STARTPTS,settb=AVTB[bodypart];"
            + "[bodypart][headpart]xfade=transition=fade:duration=\(fade):offset=\(seconds(length - 2 * crossfade))"
            + "[\(label)];"
    }

    /// `skip` ranges in the clip's own time (after `from` and `speed`).
    static func skippedRanges(for output: OutputSpec, manifest: Manifest) throws -> [ClosedRange<Double>] {
        let start = try output.from.map(manifest.resolve) ?? 0
        return try output.skip.map { pair in
            let from = try (manifest.resolve(pair[0]) - start) / output.speed
            let to = try (manifest.resolve(pair[1]) - start) / output.speed
            guard to > from else { throw SceneError.invalid("output '\(output.name)': skip ends before it starts") }
            return max(0, from) ... to
        }
    }

    /// ScreenCaptureKit writes a frame only when the screen changes, so a
    /// still ending is missing from the file: hold the last frame, then trim
    /// by the take's clock.
    private static func trim(for output: OutputSpec, manifest: Manifest) throws -> String {
        let start: Double
        var end: Double?
        if output.format == .png {
            start = try manifest.resolve(output.at ?? TimeRef(anchor: .start))
        } else {
            start = try output.from.map(manifest.resolve) ?? 0
            end = try output.to.map(manifest.resolve) ?? manifest.duration
        }
        var trim = "tpad=stop_mode=clone:stop_duration=60,trim=start=\(seconds(start))"
        if let end { trim += ":end=\(seconds(end))" }
        return trim + ",setpts=PTS-STARTPTS"
    }

    private static func fitGraph(for output: OutputSpec, input: String, output label: String) -> String {
        let lanczos = "flags=lanczos"
        guard let size = output.size else {
            let width = output.width ?? (output.format == .gif ? 960 : nil)
            guard let width else { return "[\(input)]null[\(label)]" }
            return "[\(input)]scale=\(width - width % 2):-2:\(lanczos)[\(label)]"
        }
        let width = size.width - size.width % 2
        let height = size.height - size.height % 2
        let box = "\(width):\(height)"
        if output.fit == .cover {
            return "[\(input)]scale=\(box):force_original_aspect_ratio=increase:\(lanczos),crop=\(box)[\(label)]"
        }
        let inside = "scale=\(box):force_original_aspect_ratio=decrease:\(lanczos)"
        guard output.background == "blur" else {
            let color = output.background
            return "[\(input)]\(inside),pad=\(box):(ow-iw)/2:(oh-ih)/2:color=\(color),setsar=1[\(label)]"
        }
        return "[\(input)]split[bgsrc][fgsrc];"
            + "[bgsrc]scale=\(box):force_original_aspect_ratio=increase,crop=\(box),"
            + "gblur=sigma=40,eq=brightness=-0.06[bg];"
            + "[fgsrc]\(inside)[fg];"
            + "[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1[\(label)]"
    }

    /// Screen pixels are sRGB: tagging the transfer as sRGB (not BT.709)
    /// makes browsers show a recorded background exactly as the same CSS color.
    static let colorTags = [
        "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "iec61966-2-1", "-color_range", "tv",
    ]

    private static func encoderArguments(for output: OutputSpec) -> [String] {
        switch output.format {
        case .mp4:
            [
                "-c:v", "libx264", "-preset", "slow", "-crf", "\(output.quality ?? 18)",
                "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an",
            ] + colorTags
        case .webm:
            ["-c:v", "libvpx-vp9", "-crf", "\(output.quality ?? 32)", "-b:v", "0", "-row-mt", "1", "-an"] + colorTags
        case .gif:
            ["-loop", "0"]
        case .mov:
            ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le", "-an"] + colorTags
        case .png:
            ["-frames:v", "1", "-update", "1"]
        }
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func int(_ value: Double) -> Int {
        Int(value)
    }
}
