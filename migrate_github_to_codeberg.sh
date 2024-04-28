#!/bin/bash
#
# GitHub to Codeberg Migration Script
# ------------------------------------
#
# Author: Rahul Martim Juliato
# Email: rahul.juliato@gmail.com
# License: GPL-3.0
#
# This script migrates GitHub repositories to Codeberg.
#
# User Configuration:
# --------------------
# GitHub username and personal access token
# GITHUB_USERNAME="YourGitHubUsername"
# GITHUB_TOKEN="YourGitHubToken"
#
# Codeberg username and personal access token
# CODEBERG_USERNAME="YourCodebergUsername"
# CODEBERG_TOKEN="YourCodebergToken"
#
# Define the REPOSITORIES array with repository names you want to migrate
# Leave it blank to migrate all repositories, or create a list of repositories
# if you want to select specific ones.
# REPOSITORIES=(
#     "repository1"
#     "repository2"
#     "repository3"
# )
#
# Custom prefix for description
# DESCRIPTION_PREFIX=""
# or something like:
# DESCRIPTION_PREFIX="[MIRROR] "
#
# Usage:
# ------
# 1. Configure the user settings at the beginning of the script.
# 2. Run the script.
# 3. Follow the on-screen instructions to proceed with the migration.
#
# Note: Make sure to have 'curl' and 'jq' installed.
#
# Press ENTER to continue, or C-c to abort.
#
# -----------------------------------------------------------



# USER CONFIGURATION
#---------------------------------------------------------------------------

# GitHub username and personal access token
GITHUB_USERNAME="YourGitHubUsername"
GITHUB_TOKEN="YourGitHubToken"

# Codeberg username and personal access token
CODEBERG_USERNAME="YourCodebergUsername"
CODEBERG_TOKEN="YourCodebergToken"

# Define the REPOSITORIES array with repository names you want to migrate
# Leave it blank so you migrate ALL repositories. Create a one per line list
# if you want to select the repositories to migrate.

REPOSITORIES=()
# REPOSITORIES=(
#     "aa"
#     "flycheck"
#     "my_emacs_config"
# )

# Custom prefix for description
DESCRIPTION_PREFIX="[MIRROR] "


# UTILS FUNCTIONS
#---------------------------------------------------------------------------
array_contains () { 
    local array="$1[@]"
    local seeking=$2
    local in=1
    for element in "${!array}"; do
        if [[ $element == "$seeking" ]]; then
            in=0
            break
        fi
    done
    return $in
}


# PROCESSING
#---------------------------------------------------------------------------
printf "\n    ----------------------------------------------"
printf "\n    Welcome to Github to Codeberg Migration Script"
printf "\n    ----------------------------------------------\n"
printf "\n    User on Github          : $GITHUB_USERNAME"
printf "\n    User on Codeberg        : $CODEBERG_USERNAME"
printf "\n    Using description prefix: $DESCRIPTION_PREFIX"
if [ ${#REPOSITORIES[@]} -eq 0 ]; then
    printf "\n    Migrating repo          : all"
else
    printf "\n    Migrating repos         : %s" "${REPOSITORIES[@]}"
fi
printf "\n"
printf "\n    If you wish to change this, abort and change this script.\n\n"
printf "\n\n    Press ENTER to continue, C-c to abort.\n\n"
read
printf ">>> Working...\n"


# NOTE: Github api paginates to max 100 repositories, this calculates how many
#       runs (pages) we're going to do to fetch all user data.
GITHUB_PAGINATION=100
github_total_repos=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user" | jq '.public_repos + .total_private_repos')
github_needed_pages=$(( ($github_total_repos + $GITHUB_PAGINATION - 1) / $GITHUB_PAGINATION ))


# Start Migration to Codeberg
for ((github_page_counter = 1; github_page_counter <= github_needed_pages; github_page_counter++)); do

    repos=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user/repos?per_page=${GITHUB_PAGINATION}&page=${github_page_counter}")
    
    echo "$repos" | jq -c '.[]' | while read -r row; do
        repo_name=$(echo "$row" | jq -r '.name')

        # Skips current processing repo if
        #                                 A) it is not on the wanted list
        #                             or  B) and you're migrating 'all'
        if ! array_contains REPOSITORIES "$repo_name" && [ ${#REPOSITORIES[@]} -ne 0 ]; then
            continue
        fi

        repo_clone_url=$(echo "$row" | jq -r '.clone_url')
        repo_description="$DESCRIPTION_PREFIX$(echo "$row" | jq -r '.description')"
        repo_is_private=$(echo "$row" | jq -r '.private')

        printf ">>> Migrating: $repo_name..."

        response=$(curl -s -f -w "%{http_code}" -X POST -H "Content-Type: application/json" -H "Authorization: token $CODEBERG_TOKEN" -d '{
            "auth_username": "'"$CODEBERG_USERNAME"'",
            "auth_token": "'"$CODEBERG_TOKEN"'",
            "clone_addr": "'"$repo_clone_url"'",
            "private": '$repo_is_private',
            "repo_name": "'"$repo_name"'",
            "repo_owner": "'"$CODEBERG_USERNAME"'",
            "service": "git",
            "description": "'"$repo_description"'"
        }' "https://codeberg.org/api/v1/repos/migrate")

        http_status=$(echo "$response" | awk 'END {print $NF}')
        
        case $http_status in
            201)
                printf " Success!\n"
                ;;
            409)
                printf " Error! Already exists on Codeberg.\n"
                ;;
            403)
                printf "Error! Forbidden.\n"
                ;;
            *)
                printf "Error: Unknown! $http_status\n"
                ;;
        esac
        
    done
done


echo ">>> Migration script completed!"
