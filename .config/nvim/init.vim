set number
set relativenumber
set ignorecase
set smartcase
au VimLeave * call nvim_cursor_set_shape("vertical-bar")
autocmd VimLeave * call system('printf "\e[5 q"')
set nowrap
if exists('$TMUX')
  let &t_SI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=1\x7\<Esc>\\"
  let &t_EI = "\<Esc>Ptmux;\<Esc>\<Esc>]50;CursorShape=0\x7\<Esc>\\"
else
  let &t_SI = "\<Esc>]50;CursorShape=1\x7"
  let &t_EI = "\<Esc>]50;CursorShape=0\x7"
endif
au VimLeave * call nvim_cursor_set_shape("vertical-bar")
set cursorline
se mouse+=a
color desert
set guioptions+=a
set clipboard+=unnamedplus
vnoremap <C-c> "+y
map <C-v> "+gP
cmap w!! w !SUDO_ASKPASS=/usr/lib/ssh/x11-ssh-askpass sudo -A tee > /dev/null %
