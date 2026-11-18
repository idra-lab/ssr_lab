# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias si='source install/setup.bash'
alias sd='source devel/setup.bash'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi





# ============================================================
# CUSTOM COLORED PROMPT WITH DYNAMIC IP
# ============================================================

# Get the local IPv4 address used by the default route
get_local_ip() {
    local ip

    ip=$(ip -4 route get 1.1.1.1 2>/dev/null |
         sed -n 's/.* src \([0-9.]*\).*/\1/p' |
         head -n 1)

    if [ -z "$ip" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    printf '%s' "${ip:-No-IP}"
}

# Update IP address before each prompt
update_prompt_ip() {
    PROMPT_IP=$(get_local_ip)
}

# Preserve existing PROMPT_COMMAND if present
PROMPT_COMMAND="update_prompt_ip${PROMPT_COMMAND:+;$PROMPT_COMMAND}"

# Colored terminal prompt
# Green   -> username@hostname
# Blue    -> IP address
# Cyan    -> current directory
# Default -> $ symbol
PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[01;34m\][${PROMPT_IP}]\[\033[01;36m\]:\w\[\033[00m\]\$ '

unset color_prompt force_color_prompt


# ============================================================
# NVIDIA CUDA - AUTOMATIC VERSION DETECTION
# ============================================================

CUDA_PATH=""

# Prefer the standard CUDA symbolic link
if [ -x /usr/local/cuda/bin/nvcc ]; then
    CUDA_PATH=$(readlink -f /usr/local/cuda)

else
    # Find the latest installed CUDA toolkit
    for cuda_dir in $(find /usr/local -maxdepth 1 \
        -type d -name 'cuda-[0-9]*' -print | sort -V -r); do

        if [ -x "$cuda_dir/bin/nvcc" ]; then
            CUDA_PATH="$cuda_dir"
            break
        fi
    done
fi

# Configure CUDA environment if a toolkit was found
if [ -n "$CUDA_PATH" ]; then
    export CUDA_HOME="$CUDA_PATH"

    export PATH="$CUDA_HOME/bin:$PATH"

    if [ -d "$CUDA_HOME/lib64" ]; then
        export LD_LIBRARY_PATH="$CUDA_HOME/lib64${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
fi

unset CUDA_PATH

# ============================================================
# ROS 2 FOXY - ENVIRONMENT CONFIGURATION
# ============================================================

# Source ROS 2 Foxy environment
if [ -f /opt/ros/foxy/setup.bash ]; then
    source /opt/ros/foxy/setup.bash
fi

# Source AgileX LIMO workspace if available
if [ -f "$HOME/limo_ros2_ws/install/setup.bash" ]; then
    source "$HOME/limo_ros2_ws/install/setup.bash"
fi

# ============================================================
# ROS 2 NETWORK CONFIGURATION
# ============================================================

# ROS domain ID - must match across communicating devices
export ROS_DOMAIN_ID=0

# Allow communication with remote ROS 2 nodes
export ROS_LOCALHOST_ONLY=0

# ============================================================
# CYCLONEDDS - STATIC PEER DISCOVERY
# ============================================================

# Use CycloneDDS as ROS 2 middleware
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# Load CycloneDDS configuration from the user's home directory
CYCLONEDDS_CONFIG="$HOME/cyclonedds.xml"

if [ -f "$CYCLONEDDS_CONFIG" ]; then
    export CYCLONEDDS_URI="file://$CYCLONEDDS_CONFIG"
else
    unset CYCLONEDDS_URI
fi

unset CYCLONEDDS_CONFIG
