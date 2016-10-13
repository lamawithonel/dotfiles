""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"{{{ ## Plugin Functions ##
    function! BuildComposer(info)
        if a:info.status != 'unchanged' || a:info.force
            !cargo build --release
            UpdateRemotePlugins
        endif
    endfunction
"}}}

"{{{ ## vim-plug ##
    call plug#begin()

        " Let Vundle manage Vundle
        "Plugin 'gmarik/Vundle.vim'

        " Plugins
        " -------
        Plug 'scrooloose/syntastic'
        Plug 'ynkdir/vim-vimlparser'
        Plug 'syngan/vim-vimlint'
        Plug 'godlygeek/tabular'
        Plug 'rodjek/vim-puppet'
        Plug 'noprompt/vim-yardoc'
        Plug 'wfleming/vim-codeclimate'
        Plug 'euclio/vim-markdown-composer', { 'do': function('BuildComposer') }

        " Color Schemes & Theming
        " -------------
        Plug 'chriskempson/base16-vim'
        Plug 'altercation/vim-colors-solarized'
        "Plug 'mhartington/oceanic-next'
    call plug#end()
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
    set ruler

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
    let g:syntastic_sh_checkers       = ['sh', 'shellcheck', 'checkbashims', 'bashate']
    let g:syntastic_viml_checkers     = ['vimlint']
    let g:syntastic_yaml_checkers     = ['yamlxs']

    " Theming
    " -------
    set t_Co=256
    set background=dark

    let base16colorspace=256

    colorscheme solarized
    let g:solarized_termcolors=256
    let g:solarized_hitrail=1

    "colorscheme OceanicNext


    " Trailing space warnings
    " -----------------------
    hi TrailingSpace ctermbg=red guibg=#dc322f

" }}} end options


" vim:foldmethod=marker
