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
        Plug 'terryma/vim-multiple-cursors'

        " Color Schemes & Theming
        " -------------
        Plug 'vim-airline/vim-airline'
        Plug 'vim-airline/vim-airline-themes'
        Plug 'chriskempson/base16-vim'
        Plug 'altercation/vim-colors-solarized'
        "Plug 'mhartington/oceanic-next'
        "Plug 'trusktr/seti.vim'
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
    set expandtab
    set history=256
    set viminfo='256,\"1024
    set ruler


    " Column highlighting and test pattern
    " ----------------------------------
    set colorcolumn=72,80,100,120,140
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

    " Vim-Airline
    " -----------
    let g:airline_theme = 'base16_solarized'
    if !exists('g:airline_symbols')
        let g:airline_symbols = {}
    endif
    let g:airline_left_sep  = '▶'
    let g:airline_right_sep = '◀'
    let g:airline_symbols.branch = '𝌎'
    let g:airline_symbols.branch = '⎇'
    let g:airline_symbols.branch = 'ᚵ'
    let g:airline_symbols.branch = 'ᚴ'

    " Theming
    " -------
    set t_Co=256

    "if filereadable(expand("~/.vimrc_background"))
    "    "let base16colorspace=256
    "    source ~/.vimrc_background
    "endif

    colorscheme solarized
    set background=dark
    let g:solarized_termcolors=256
    let g:solarized_hitrail=1

    "colorscheme OceanicNext

    "colorscheme seti


    " Trailing space warnings
    " -----------------------
    hi TrailingBlanks ctermbg=red guibg=#dc322f
    call matchadd('TrailingBlanks', '[[:blank:]]\+$')

    " Key Bindings
    " ------------
    map <F7> :set spell! spelllang=en_us spellfile=~/.vim/spellfile.add<cr>

" }}} end options


" vim:foldmethod=marker
