set number
set nowrap
set ignorecase
set smartcase
set cursorline
set hlsearch
set incsearch

" Cursor shape: beam in insert, block in normal
if exists('$TMUX')
  let &t_SI = "\<Esc>Ptmux;\<Esc>\e[5 q\<Esc>\\"
  let &t_EI = "\<Esc>Ptmux;\<Esc>\e[1 q\<Esc>\\"
else
  let &t_SI = "\e[5 q"
  let &t_EI = "\e[1 q"
endif

" Restore beam cursor on exit
autocmd VimLeave * call system('printf "\e[5 q"')
