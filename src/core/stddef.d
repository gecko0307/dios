module core.stddef;

extern(C) @nogc nothrow:

alias typeof(cast(void*)0 - cast(void*)0) ptrdiff_t;

alias dchar wint_t;
alias dchar wchar_t;
alias dchar wctype_t;
alias dchar wctrans_t;

const dchar WEOF = 0xFFFF;
