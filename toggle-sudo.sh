#!/bin/zsh

# Get the current username
USERNAME=$(whoami)

# Sudoers file location
SUDOERS_FILE="/etc/sudoers"
TMP_FILE="/tmp/sudoers.tmp"

# Check for -a (add) or -r (remove) flag
while getopts "ar" opt; do
  case $opt in
    a)  # Add NOPASSWD for current user
        sudo cp $SUDOERS_FILE $TMP_FILE
        if ! sudo grep -q "^$USERNAME ALL=(ALL) NOPASSWD: ALL" $SUDOERS_FILE; then
          echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" | sudo tee -a $TMP_FILE > /dev/null
          sudo visudo -c -f $TMP_FILE && sudo mv $TMP_FILE $SUDOERS_FILE
          echo "NOPASSWD added for $USERNAME."
        else
          echo "NOPASSWD already set for $USERNAME."
        fi
        ;;
    r)  # Remove NOPASSWD for current user
        sudo cp $SUDOERS_FILE $TMP_FILE
        sudo sed -i '' "/^$USERNAME ALL=(ALL) NOPASSWD: ALL/d" $TMP_FILE
        sudo visudo -c -f $TMP_FILE && sudo mv $TMP_FILE $SUDOERS_FILE
        echo "NOPASSWD removed for $USERNAME."
        ;;
    *)  # Invalid option
        echo "Usage: $0 -a (add NOPASSWD) or -r (remove NOPASSWD)"
        exit 1
        ;;
  esac
done

# If no option is provided, display usage
if [[ $OPTIND -eq 1 ]]; then
  echo "Usage: $0 -a (add NOPASSWD) or -r (remove NOPASSWD)"
  exit 1
fi
