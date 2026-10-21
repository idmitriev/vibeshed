#!/bin/zsh
# Terminal tools for clip-theming, run in the VM by its `prepare` step:
# Neovim draws with the terminal's 16 ANSI colors (so Ghostty's palette —
# and every theme Vibeshed applies to Ghostty — colors it too), and lsd uses
# the colors Vibeshed writes to ~/.config/lsd/colors.yaml.
set -e

mkdir -p ~/.config/nvim ~/.config/lsd
cat > ~/.config/nvim/init.lua <<'EOF'
-- showreel: the terminal's ANSI palette, so Ghostty's theme reaches Neovim
vim.opt.termguicolors = false
vim.cmd.colorscheme("vim")
vim.opt.number = true
vim.opt.signcolumn = "no"
vim.opt.shortmess:append("I")
vim.opt.wrap = false
vim.opt.title = true
vim.opt.titlestring = "%t — nvim"
EOF
cat > ~/.config/lsd/config.yaml <<'EOF'
# showreel: Vibeshed's lsd theme target writes colors.yaml for `theme: custom`
color:
  theme: custom
icons:
  when: never
EOF
echo "terminal tools configured"
