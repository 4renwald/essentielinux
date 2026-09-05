if status is-interactive
    if type -q starship
        starship init fish | source
    end

    if type -q direnv
        direnv hook fish | source
    end

    if type -q zoxide
        zoxide init fish --cmd cd | source
    end

    if type -q eza
        alias ls='eza --icons --group-directories-first -1'
    end

    if type -q lazygit
        abbr lg lazygit
    end
    abbr gd 'git diff'
    abbr ga 'git add .'
    abbr gc 'git commit -am'
    abbr gl 'git log'
    abbr gs 'git status'
    abbr gst 'git stash'
    abbr gsp 'git stash pop'
    abbr gp 'git push'
    abbr gpl 'git pull'
    abbr gsw 'git switch'
    abbr gsm 'git switch main'
    abbr gb 'git branch'
    abbr gbd 'git branch -d'
    abbr gco 'git checkout'
    abbr gsh 'git show'

    abbr l 'ls -l'
    abbr ll 'ls -la'
    abbr la 'ls -a'
    abbr lla 'ls -la'

    function mark_prompt_start --on-event fish_prompt
        echo -en '\e]133;A\e\\'
    end
end
