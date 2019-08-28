""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"{{{ ## Plugin Functions ##
    "Initialize vim-markdown-composer
    if has('nvim')
        function! BuildComposer(info)
            if a:info.status != 'unchanged' || a:info.force
                !cargo build --release
                UpdateRemotePlugins
            endif
        endfunction
    endif
"}}}

"{{{ ## vim-plug ##
    call plug#begin()

        " Plugins
        " -------
        Plug 'scrooloose/syntastic'
        Plug 'ynkdir/vim-vimlparser'
        Plug 'syngan/vim-vimlint'
        Plug 'godlygeek/tabular'
        Plug 'rodjek/vim-puppet'
        Plug 'noprompt/vim-yardoc'
        Plug 'wfleming/vim-codeclimate'
        Plug 'terryma/vim-multiple-cursors'
        Plug 'tangledhelix/vim-kickstart'
        Plug 'hashivim/vim-consul'
        Plug 'hashivim/vim-packer'
        Plug 'hashivim/vim-terraform'
        Plug 'hashivim/vim-vagrant'
        Plug 'hashivim/vim-vaultproject'
        Plug 'gentoo/gentoo-syntax'
        Plug 'rust-lang/rust.vim'
        Plug 'vim-scripts/dhcpd.vim'
        Plug 'PProvost/vim-ps1'
        Plug 'https://anongit.gentoo.org/git/proj/eselect-syntax.git'

        if has('nvim')
            Plug 'euclio/vim-markdown-composer'
        endif

        " Color Schemes & Theming
        " -------------
        Plug 'vim-airline/vim-airline'
        Plug 'vim-airline/vim-airline-themes'
        Plug 'chriskempson/base16-vim'
    call plug#end()
"}}}

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"{{{ ## Options & Settings ##

    scriptencoding utf-8
    set nocompatible
    set number
    set mouse=i
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
    let g:syntastic_python_checkers   = ['flake8', 'mypy']
    let g:syntastic_rst_checkers      = ['rstcheck']
    let g:syntastic_ruby_checkers     = ['mri', 'rubocop', 'reek', 'flog']
    let g:syntastic_sh_checkers       = ['sh', 'shellcheck', 'checkbashims', 'bashate']
    let g:syntastic_viml_checkers     = ['vimlint']
    let g:syntastic_yaml_checkers     = ['yamlxs']

    let g:syntastic_sh_bashate_args   = '--ignore E002,E003'
    let g:syntastic_sh_shellcheck_args = '-x'

    " Vim-Airline
    " -----------
    let g:airline_theme = 'base16_default'
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

    if (&t_Co >= 256) && (($TERM !~# '^konsole') && empty($KONSOLE_PROFILE_NAME))
        let g:base16colorspace = 256
    elseif (&t_Co >= 88)
        set t_Co=88
        let g:base16colorspace = 88
    elseif (&t_Co >= 16)
        set t_Co=16
        let g:base16colorspace = 16
    elseif (&t_Co >=8)
        set t_Co=8
        let g:base16colorspace = 8
    endif

    if filereadable(expand("~/.vimrc_background"))
       source ~/.vimrc_background
    else
       colorscheme base16-default-dark
    endif

    " Trailing space warnings
    " -----------------------
    hi TrailingBlanks ctermbg=red guibg=#dc322f
    call matchadd('TrailingBlanks', '[[:blank:]]\+$')

    " Key Bindings
    " ------------
    map <F7> :set spell! spelllang=en_us spellfile=~/.vim/spellfile.add<cr>

" }}} end options


" vim:foldmethod=marker
