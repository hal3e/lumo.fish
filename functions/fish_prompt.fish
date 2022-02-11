# State used for memoization and async calls.
set -g __lucid_cmd_id 0
set -g __lucid_git_state_cmd_id -1
set -g __lucid_git_static ""
set -g __lucid_dirty ""
set -g __lucid_color (set_color normal)

# Increment a counter each time a prompt is about to be displayed.
# Enables us to distingish between redraw requests and new prompts.
function __lucid_increment_cmd_id --on-event fish_prompt
    set __lucid_cmd_id (math $__lucid_cmd_id + 1)
end

# Abort an in-flight dirty check, if any.
function __lucid_abort_check
    if set -q __lucid_check_pid
        set -l pid $__lucid_check_pid
        functions -e __lucid_on_finish_$pid
        command kill $pid > /dev/null 2>&1
        set -e __lucid_check_pid
    end
end

function __lucid_git_status
    # Reset state if this call is *not* due to a redraw request
    set -l prev_dirty $__lucid_color
    if test $__lucid_cmd_id -ne $__lucid_git_state_cmd_id
        __lucid_abort_check

        set __lucid_git_state_cmd_id $__lucid_cmd_id
        set __lucid_git_static ""
        set __lucid_dirty ""
        set  __lucid_color (set_color normal)
    end

    # Fetch git position & action synchronously.
    # Memoize results to avoid recomputation on subsequent redraws.
    if test -z $__lucid_git_static
        # Determine git working directory
        set -l git_dir (command git --no-optional-locks rev-parse --absolute-git-dir 2>/dev/null)
        if test $status -ne 0
            return 1
        end

        set -l position (command git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
        if test $status -ne 0
            # Denote detached HEAD state with short commit hash
            set position (command git --no-optional-locks rev-parse --short HEAD 2>/dev/null)
            if test $status -eq 0
                set position "@$position"
            end
        end

        set -g __lucid_git_static $position
    end

    # Fetch dirty status asynchronously.
    if test -z $__lucid_dirty
        if ! set -q __lucid_check_pid
            # Compose shell command to run in background
            set -l check_cmd "git --no-optional-locks status -unormal --porcelain --ignore-submodules 2>/dev/null | head -n1 | count"
            set -l cmd "if test ($check_cmd) != "0"; exit 1; else; exit 0; end"

            begin
                # Defer execution of event handlers by fish for the remainder of lexical scope.
                # This is to prevent a race between the child process exiting before we can get set up.
                block -l

                set -g __lucid_check_pid 0
                command fish --private --command "$cmd" >/dev/null 2>&1 &
                set -l pid (jobs --last --pid)

                set -g __lucid_check_pid $pid

                # Use exit code to convey dirty status to parent process.
                function __lucid_on_finish_$pid --inherit-variable pid --on-process-exit $pid
                    functions -e __lucid_on_finish_$pid

                    if set -q __lucid_check_pid
                        if test $pid -eq $__lucid_check_pid
                            switch $argv[3]
                                case 0
                                    set -g __lucid_dirty_state 0
                                    if status is-interactive
                                        commandline -f repaint
                                    end
                                case 1
                                    set -g __lucid_dirty_state 1
                                    if status is-interactive
                                        commandline -f repaint
                                    end
                                case '*'
                                    set -g __lucid_dirty_state 2
                                    if status is-interactive
                                        commandline -f repaint
                                    end
                            end
                        end
                    end
                end
            end
        end

        if set -q __lucid_dirty_state
            switch $__lucid_dirty_state
                case 0
                    set -g __lucid_color (set_color $fish_color_command)
                case 1
                    set -g __lucid_color (set_color $fish_color_error)
                case 2
                    set -g __lucid_color (set_color $fish_color_error)
            end

            set -e __lucid_check_pid
            set -e __lucid_dirty_state
        end
    end

    # Render git status. When in-progress, use previous state to reduce flicker.
    set -l color (set_color normal)
    if ! test -z $__lucid_color
      echo -sn "$__lucid_color($color$__lucid_git_static$__lucid_color) >"
    else if ! test -z $prev_dirty
      echo -sn "$__lucid_color($color$__lucid_git_static$__lucid_color) >"
    end

    set_color normal
end

function fish_prompt
    set -l status_copy $status
    set -l pwd_info (pwd_info "/")
    set -l dir
    set -l base
    set -l color (set_color white)
    set -l color2 (set_color normal)
    set -l color3 (set_color $fish_color_command)
    set -l color_error (set_color $fish_color_error)
    set -l color_normal "$color2"

    echo -sn " "

    if test "$status_copy" -ne 0
        set color "$color_error"
        set color2 "$color_error"
        set color3 "$color_error"
    end

    set -l glyph " $color2>$color_normal"

    if test 0 -eq (id -u "$USER")
        echo -sn "$color_error# $color_normal"
    end

    if test ! -z "$SSH_CLIENT"
        set -l color "$color2"

        if test 0 -eq (id -u "$USER")
            set color "$color_error"
        end

        echo -sn "$color"(host_info "user@")"$color_normal"
    end

    if test "$PWD" = ~
        set base "$color3~"
        set glyph

    else if pwd_is_home
        set dir

    else
        if test "$PWD" = /
            set glyph
        else
            set dir "/"
        end

        set base "$color_error/"
    end

    if test ! -z "$pwd_info[1]"
        set base "$pwd_info[1]"
    end

    if test ! -z "$pwd_info[2]"
        set dir "$dir$pwd_info[2]/"
    end

    echo -sn "$color2$dir$color$base$color_normal"

    if test ! -z "$pwd_info[3]"
        echo -sn "$color2/$pwd_info[3]"
    end

    set -l cwd (pwd | string replace "$HOME" '~')

    if test $cwd != '~'
        set -l git_state (__lucid_git_status)
        if test $status -eq 0
            echo -sn " $git_state"
        else
            echo -sn " >"
        end

    end
    echo -sn " "
end
