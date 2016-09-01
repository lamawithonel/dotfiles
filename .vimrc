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
        Plugin 'noprompt/vim-yardoc'
        Plugin 'wfleming/vim-codeclimate'
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

    set colorcolumn=72,80,100,120,140

    " Column test pattern
    " ---------------------------
    "    10........20        30........40        50........60          72......80        90........100       110.......120       130...... 140
    "    |         |         |         |         |         |           |       |         |         |         |         |         |         |

    " File type detection
    " -------------------
    au BufNewFile,BufRead *.markdown,*.mdown,*.mkd,*.mkdn,*.mdwn,*.md set ft=markdown

    " Per file type indentation
    " -------------------------
    au FileType python setl sw=4 sts=4 et
    au FileType ruby   setl sw=2 sts=2 et
    au FileType vim    setl sw=4 sts=4 et

    " Syntastic settings
    " ------------------
    let g:syntastic_css_checkers      = ['phpcs']
    let g:syntastic_markdown_checkers = ['mdl']
    let g:syntastic_puppet_checkers   = ['puppet', 'puppetlint']
    let g:syntastic_python_checkers   = ['flake8']
    let g:syntastic_rst_checkers      = ['rstcheck']
    let g:syntastic_ruby_checkers     = ['mri', 'rubocop', 'reek', 'flog']
    let g:syntastic_sh_checkers       = ['sh', 'checkbashims', 'bashate', 'shellcheck']
    let g:syntastic_viml_checkers     = ['vimlint']
    let g:syntastic_yaml_checkers     = ['yamlxs']

    " Theming
    " -------
    set background=dark
    colorscheme solarized
    let g:solarized_termcolors=256
    let g:solarized_hitrail=1


    " Trailing space warnings
    " -----------------------
    hi TrailingSpace ctermbg=red guibg=#dc322f

" }}} end options


" vim:foldmethod=marker
