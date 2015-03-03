""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"{{{ ## Vundle Plugin Manager ##

    filetype off
    set rtp+=~/.vim/bundle/Vundle.vim " add Vundle to the runtime path
    call vundle#begin()               " initialize

        " Let Vundle manage Vundle
        Plugin 'gmarik/Vundle.vim'

        " Plugins
        " -------
        Plugin 'altercation/vim-colors-solarized'
        Plugin 'scrooloose/syntastic'
        Plugin 'ynkdir/vim-vimlparser'
        Plugin 'syngan/vim-vimlint'
        Plugin 'godlygeek/tabular'
        Plugin 'rodjek/vim-puppet'
    call vundle#end()
    filetype plugin indent on

    "{{{ (Vundle Examples)

        " Repos on GitHub
        " ---------------

        "Plugin 'tpope/vim-fugitive'
        "Plugin 'Lokaltog/vim-easymotion'
        "Plugin 'rstacruz/sparkup', {'rtp': 'vim/'}
        "Plugin 'tpope/vim-rails.git'

        " vim-scripts.org repos
        " ---------------------

        "Plugin 'L9'
        "Plugin 'FuzzyFinder'

        " Generic Git repos
        " -----------------

        "Plugin 'git://git.wincent.com/command-t.git'

        " Special Overrides
        " -----------------

        " Set the runtimepath (rtp) to a sub-directory of a repo
        "Plugin 'rstacruz/sparkup', {'rtp': 'vim/'}

        " Change the name of a plugin
        "Plugin 'user/L9', {'name': 'newL9'} 

    "}}}

    "{{{ (Vundle Command Reference)


    " :PluginList          - list configured bundles
    " :PluginInstall(!)    - install(update) bundles
    " :PluginSearch(!) foo - search(or refresh cache first) for foo
    " :PluginClean(!)      - confirm(or auto-approve) removal of unused bundles
    "
    " NOTE: comments after Plugin command are not allowed.
    "
    " See Also: ":h vundle" and "https://github.com/gmarik/vundle/wiki"

    "}}}
"}}}

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"{{{ ## Options & Settings ##

    set nocompatible
    syntax enable
    filetype plugin on
    filetype indent on
    set backspace=indent,eol,start
    set ts=4
    set sw=4
    set history=256
    set viminfo='256,\"1024

    " Per file type indentation
    " -------------------------
    au FileType python setl sw=4 sts=4 et
    au FileType ruby   setl sw=2 sts=2 et
    au FileType vim    setl sw=4 sts=4 et

    " Syntastic settings
    " ------------------
    let g:syntastic_puppet_checkers = ['puppet', 'puppetlint']
    let g:syntastic_yaml_checkers   = ['yamlxs']

    " Theming
    " -------
    set background=dark
    colorscheme solarized
    let g:solarized_termcolors=256
    let g:solarized_hitrail=1

    " Column warnings
    " ---------------
    augroup ColumnWarn
        hi ColumnWarn1 ctermbg=0 guibg=#073642
        hi ColumnWarn2 ctermbg=0 guibg=#073642 ctermfg=245 guifg=#93a1a1
        hi ColumnWarn3 ctermbg=0 guibg=#073642 ctermfg=166 guifg=#cb4b16
        autocmd BufWinEnter * let w:m2=matchadd('ColumnWarn1', '\%73v.\+', -1)
        autocmd BufWinEnter * let w:m2=matchadd('ColumnWarn2', '\%81v.\+', -1)
        autocmd BufWinEnter * let w:m2=matchadd('ColumnWarn3', '\%121v.\+', -1)
    augroup END

    " Test Pattern
    " ------------
    "    10........20        30........40        50........60          72......80        90........100       110.......120......130       140

    " Trailing space warnings
    " -----------------------
    hi TrailingSpace ctermbg=red guibg=#dc322f

" }}} end options


" vim:foldmethod=marker
