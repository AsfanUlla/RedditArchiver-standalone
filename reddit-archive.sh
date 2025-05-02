# Download a Reddit thread using RedditArchiver
# 
# Installation
# ------------
# You can add this function to your .bashrc or .zshrc with:
#
# local REDDIT_ARCHIVER_REPO=~
# source $REDDIT_ARCHIVER_REPO/RedditArchiver-standalone/reddit-archive.sh
# 
# (Use the directory you cloned the repository for REDDIT_ARCHIVER_REPO.)
#
# Usage
# -----
#     reddit_archive https://www.reddit.com/r/Superbowl/comments/14hczkk/elf_owl_enjoying_our_pond/
#     reddit_archive 14iard6
#
# Unlike the RedditArchiver.py script itself, you can only specify ONE submission ID or URL.
#
# Customization
# -------------
# There are several environment variables to allow customization of paths/files:
#
# REDDIT_ARCHIVER_SCRIPT_DIR                    Directory where RedditArchiver.py lives 
# REDDIT_ARCHIVER_SCRIPT_NAME                   Name of the script itself
# REDDIT_ARCHIVER_VENV_PATH                     Path to the Python virtual environment
# REDDIT_ARCHIVER_OUTPUT_DIR                    Directory where the file will be saved
# REDDIT_ARCHIVER_CONFIG_FILE                   Pathname to config file
# REDDIT_ARCHIVER_REFRESH_TOKEN_SECRET_FILE     Pathname to encrypted refresh token
#
# If REDDIT_ARCHIVER_REFRESH_TOKEN_SECRET_FILE is set, Actually Good Encryption 
# (age) is used to decrypt the refresh token using a passkey. See 
# https://github.com/FiloSottile/age for more. If you use something else such as
# gpg, make appropriate changes.
#
# Security
# --------
# The combination of a custom pathname to the config file and pathname to an
# encrypted refresh token provides for more security than the out-of-the-box 
# RedditArchiver.py provides. After running authentication.py to get the client ID,
# secret, and refresh token:
#
# 1. Move the config.yml file to e.g. ~/.secrets/RedditArchiver.config.yml. Set
#    REDDIT_ARCHIVER_CONFIG_FILE to this pathname.
# 2. Edit this file and remove the refresh token. Provide the client ID and secret
#    values from your Reddit app at https://www.reddit.com/prefs/apps/. 
#    (If you aren't sure: the client ID is the string under the 'personal use script' 
#    label, and the secret is, unsurprisingly, next to the 'secret' label.)
# 3. Assuming you're using age, you can use the reddit_archiver_encrypt_refresh_token
#    function to encrypt your refresh token (path is an example):
#      reddit_archiver_encrypt_refresh_token ~/.secrets/RedditArchiver.refreshtoken.age
#    Then in your .bashrc or .zshrc:
#      export REDDIT_ARCHIVER_REFRESH_TOKEN_SECRET_FILE=~/.secrets/RedditArchiver.refreshtoken.age
#
# This keeps your refresh token out of the filesystem. Additionally, the reddit_archive
# function passes the decrypted refresh token to the Python script as an environment 
# variable, to keep it off the command line.
#

reddit_archiver_encrypt_refresh_token() {
  local refresh_token
  local output_file="$1"

  if [[ -z "$output_file" ]]; then
    echo "No output filename was provided, exiting"
    return 1
  fi

  read -s "?Enter Refresh Token: " refresh_token
  echo 

  echo "$refresh_token" | age -p -o "$output_file"
}

reddit_archive() {
  # Check if a URL argument was provided
  if [[ -z "$1" ]]; then
    echo "Usage: reddit_archive <reddit_thread_url>"
    return 1
  fi

  # --- Configuration ---
  local script_dir="${REDDIT_ARCHIVER_SCRIPT_DIR:-$HOME/RedditArchiver-standalone}"
  local script_name="${REDDIT_ARCHIVER_SCRIPT_NAME:-RedditArchiver.py}"
  local script_path="$script_dir/$script_name"
  local venv_path="${REDDIT_ARCHIVER_VENV_PATH:-$script_dir/venv}" 
  local venv_activate_path="$venv_path/bin/activate" 
  local output_dir="${REDDIT_ARCHIVER_OUTPUT_DIR:-$HOME/RedditPosts}"
  local config_file="${REDDIT_ARCHIVER_CONFIG_FILE:-$script_dir/config.yml}"
  local reddit_url="$1"
  
  if [[ -v REDDIT_ARCHIVER_REFRESH_TOKEN_SECRET_FILE ]]; then
    local refresh_token=$(age -d -o - $REDDIT_ARCHIVER_REFRESH_TOKEN_SECRET_FILE )
  fi

  # --- End Configuration ---

  # --- Prerequisite Checks ---
  if [[ ! -f "$script_path" ]]; then
    echo "Error: RedditArchiver script not found at '$script_path'"
    return 1
  fi
  if [[ ! -f "$venv_activate_path" ]]; then
    echo "Error: Virtual environment activate script not found at '$venv_activate_path'"
    echo "Please ensure the virtual environment exists and is set up correctly."
    return 1
  fi
  if [[ ! -d "$output_dir" ]]; then
          echo "Error: Output directory '$output_dir' doesn't exist, isn't a directory, or can't be accessed (permissions)."
     return 1
  fi

  # --- Environment Management ---
  local original_venv="$VIRTUAL_ENV" # Save current VIRTUAL_ENV path (if any)
  local script_failed=0 # Flag to track script success/failure

  # --- Activate Target Venv ---
  # Deactivate any current environment first, just in case activate doesn't handle nesting well
  if [[ -n "$original_venv" ]] && command -v deactivate &> /dev/null; then
      echo "Deactivating current venv ($original_venv) temporarily..."
      deactivate
  fi

  # Source the target venv's activate script
  source "$venv_activate_path"

  # --- Execute the Script ---
  # Use 'python' now, as the correct one should be in PATH from the activated venv
  echo "Running python $script_path -c $config_file -i $reddit_url -o $output_dir"
  if ! refresh_token=$refresh_token python "$script_path" "-c" "$config_file" "-i" "$reddit_url" "-o" "$output_dir" ; then
    echo "Error: RedditArchiver script failed with exit code $?."
    script_failed=1
  fi

  # --- Restore Original Environment ---
  if command -v deactivate &> /dev/null; then
    deactivate
  else
    echo "Warning: 'deactivate' command not found for $script_name."
  fi

  # Reactivate original environment if one existed
  if [[ -n "$original_venv" ]]; then
    local original_activate_path="${original_venv}/bin/activate"
    if [[ -f "$original_activate_path" ]]; then
      source "$original_activate_path"
    else
      echo "Warning: Could not find activate script for original venv at '$original_activate_path'."
      echo "Original environment may not be fully restored."
    fi
  fi

  return $script_failed
}

