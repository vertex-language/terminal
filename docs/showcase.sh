#!/bin/zsh
# The README's screenshot: what each pane shows, then a plain shell. From
# the repository's folder, with docs/showcase.json as the settings:
#
#     VERTEX_TERMINAL_SETTINGS=docs/showcase.json vsc run terminal -- --dark \
#       new-tab --title vertex --tabColor "#61AFEF" zsh docs/showcase.sh colors \; \
#       split-pane -V -s 0.42 zsh docs/showcase.sh log ../vsc \; \
#       split-pane -H -s 0.42 zsh docs/showcase.sh files . \; \
#       new-tab --title build --tabColor "#98C379" zsh -f \; \
#       new-tab --title logs --tabColor "#E06C75" zsh -f \; \
#       focus-tab -t 0 \; focus-pane -t 0 --snapshot docs/screenshot.png --snapshot-after 4
e=$'\e'
r="${e}[0m"
prompt() {
    export PS1="%F{6}vertex%f %F{8}%1~%f %F{5}❯%f "
    exec zsh -f -i
}

case "$1" in
colors)
    printf "\n  ${e}[1mVertex Terminal$r  ${e}[2mthe emulator, the renderer and the window, in Vertex$r\n\n"
    printf "  ${e}[2m16 colors$r\n  "
    for i in {0..15}; do printf "${e}[48;5;${i}m    $r"; done
    printf "\n\n  ${e}[2m256 colors$r\n"
    for row in {0..5}; do
        printf "  "
        for c in {0..35}; do printf "${e}[48;5;$((16 + row * 36 + c))m $r"; done
        printf "  "
        for g in {0..5}; do printf "${e}[48;5;$((232 + row * 4 + g % 4))m $r"; done
        printf "\n"
    done
    printf "\n  ${e}[2m24-bit color$r\n"
    awk 'function c(x){return int(x<0?0:(x>255?255:x))}
    function hue(h,k,  r,g,b,f){h=h*6; f=h-int(h)
        if(h<1){r=255;g=255*f;b=0}else if(h<2){r=255*(1-f);g=255;b=0}else if(h<3){r=0;g=255;b=255*f}
        else if(h<4){r=0;g=255*(1-f);b=255}else if(h<5){r=255*f;g=0;b=255}else{r=255;g=0;b=255*(1-f)}
        return c(r*k)";"c(g*k)";"c(b*k)}
    BEGIN{n=60; for(row=0;row<3;row++){s="  "; for(i=0;i<n;i++){
        if(row==0) col=hue(i/n,1); else if(row==1) col=hue(i/n,0.5); else {v=int(i*255/(n-1)); col=v";"v";"v}
        s=s sprintf("\033[48;2;%sm ",col)} print s "\033[0m"}}'
    printf "\n  ${e}[1mbold$r  ${e}[2mdim$r  ${e}[3mitalic$r  ${e}[4munderline$r  ${e}[4:3m${e}[58;5;9mcurly$r  ${e}[4:2mdouble$r  ${e}[4:4mdotted$r  ${e}[9mstrike$r  ${e}[7m inverse $r\n"
    printf "  ${e}[38;5;214m日本語$r · ${e}[38;5;117m한국어$r · ${e}[38;5;156mΩ≈ç√∫$r · 🚀 ✨ 🎨 · ▁▂▃▄▅▆▇█\n"
    printf "  ${e}]8;;https://github.com/vertex-language/terminal${e}\\\\${e}[38;5;111mgithub.com/vertex-language/terminal${e}]8;;${e}\\\\$r  ${e}[2m(a hyperlink: ⌘-click)$r\n\n"
    prompt
    ;;
log)
    printf "${e}[2m❯ git log --graph --oneline$r\n"
    git --no-pager -C "${2:-.}" log --graph --color=always -n 15 --format='%C(yellow)%h%Creset %<(40,trunc)%s %C(blue)%ar%Creset' 
    printf "\n"
    prompt
    ;;
files)
    printf "${e}[2m❯ ls -l$r\n"
    CLICOLOR_FORCE=1 ls -lhG "${2:-.}" | tail -n +2 | awk '{ $3=""; $4=""; print }' | sed 's/   */  /'
    printf "\n"
    prompt
    ;;
esac
