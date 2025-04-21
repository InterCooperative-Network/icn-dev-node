#!/bin/bash
set -euo pipefail

# ICN Template Registry Script
# Manages a repository of DSL templates for common operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/node-state.sh"

# Default values
DATA_DIR="${HOME}/.icn"
TEMPLATES_DIR="${DATA_DIR}/templates"
QUEUE_DIR="${DATA_DIR}/queue"
DEFAULT_TEMPLATES_DIR="${SCRIPT_DIR}/../templates"
TEMPLATE_NAME=""
TEMPLATE_OUTPUT=""
VERBOSE=false
LIST_ONLY=false
SHOW_CONTENT=false
APPLY_TEMPLATE=false
FORCE=false
CUSTOM_VARS=()

print_usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [COMMAND]

Manage DSL templates for common ICN operations.

Commands:
  list                   List available templates
  show TEMPLATE          Show contents of a specific template
  add PATH [NAME]        Add a new template from a file
  apply TEMPLATE [OUT]   Apply a template to create a new DSL file
  remove TEMPLATE        Remove a template from the registry

Options:
  --data-dir DIR         Data directory (default: ${DATA_DIR})
  --templates-dir DIR    Templates directory (default: ${DATA_DIR}/templates)
  --output FILE          Output file for applied template
  --queue                Queue the generated file for execution
  --var KEY=VALUE        Set a custom variable for template substitution
  --force                Force overwrite existing files
  --verbose              Enable verbose output
  --help                 Display this help message and exit

Examples:
  # List all available templates
  $(basename "$0") list

  # Show the contents of a template
  $(basename "$0") show governance/proposal

  # Add a custom template
  $(basename "$0") add my_template.dsl governance/custom

  # Apply a template with variables
  $(basename "$0") apply governance/proposal --var title="Add new peer" --var peer_id="QmHash"
  
  # Apply a template and queue for execution
  $(basename "$0") apply governance/vote --var vote="yes" --queue
EOF
}

parse_args() {
  local command=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --data-dir)
        DATA_DIR="$2"
        TEMPLATES_DIR="${DATA_DIR}/templates"
        QUEUE_DIR="${DATA_DIR}/queue"
        shift 2
        ;;
      --templates-dir)
        TEMPLATES_DIR="$2"
        shift 2
        ;;
      --output)
        TEMPLATE_OUTPUT="$2"
        shift 2
        ;;
      --queue)
        APPLY_TEMPLATE=true
        shift
        ;;
      --var)
        CUSTOM_VARS+=("$2")
        shift 2
        ;;
      --force)
        FORCE=true
        shift
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --help)
        print_usage
        exit 0
        ;;
      list)
        LIST_ONLY=true
        shift
        ;;
      show)
        SHOW_CONTENT=true
        if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
          TEMPLATE_NAME="$2"
          shift 2
        else
          log_error "Template name required for 'show' command"
          print_usage
          exit 1
        fi
        ;;
      add)
        command="add"
        if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
          local template_path="$2"
          shift 2
          
          # Optional template name parameter
          if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
            TEMPLATE_NAME="$1"
            shift
          else
            # Use filename without extension as template name
            TEMPLATE_NAME=$(basename "$template_path" .dsl)
          fi
          
          # Save for later use by command
          TEMPLATE_OUTPUT="$template_path"
        else
          log_error "Template path required for 'add' command"
          print_usage
          exit 1
        fi
        ;;
      apply)
        command="apply"
        APPLY_TEMPLATE=true
        if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
          TEMPLATE_NAME="$2"
          shift 2
          
          # Optional output file
          if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
            TEMPLATE_OUTPUT="$1"
            shift
          fi
        else
          log_error "Template name required for 'apply' command"
          print_usage
          exit 1
        fi
        ;;
      remove)
        command="remove"
        if [[ $# -gt 1 && ! "$2" =~ ^-- ]]; then
          TEMPLATE_NAME="$2"
          shift 2
        else
          log_error "Template name required for 'remove' command"
          print_usage
          exit 1
        fi
        ;;
      -*)
        log_error "Unknown option: $1"
        print_usage
        exit 1
        ;;
      *)
        log_error "Unknown command: $1"
        print_usage
        exit 1
        ;;
    esac
  done

  # Set default action if none specified
  if [[ -z "$command" && "$LIST_ONLY" == false && "$SHOW_CONTENT" == false ]]; then
    LIST_ONLY=true
  fi

  return 0
}

validate_args() {
  # Create necessary directories
  mkdir -p "$TEMPLATES_DIR" "$QUEUE_DIR"

  # If we're listing, showing, or applying a template, make sure templates dir exists
  if [[ "$LIST_ONLY" == true || "$SHOW_CONTENT" == true || "$APPLY_TEMPLATE" == true ]]; then
    if [[ ! -d "$TEMPLATES_DIR" ]]; then
      log_error "Templates directory not found: $TEMPLATES_DIR"
      return 1
    fi
  fi

  # If showing or applying, make sure template name is provided
  if [[ "$SHOW_CONTENT" == true || "$APPLY_TEMPLATE" == true ]]; then
    if [[ -z "$TEMPLATE_NAME" ]]; then
      log_error "Template name is required"
      return 1
    fi
  fi

  return 0
}

# Initialize the template registry with default templates if not present
initialize_templates() {
  if [[ ! -d "$DEFAULT_TEMPLATES_DIR" ]]; then
    log_warn "Default templates directory not found: $DEFAULT_TEMPLATES_DIR"
    return 1
  fi

  # Check if templates directory is empty
  if [[ -z "$(ls -A "$TEMPLATES_DIR" 2>/dev/null)" ]]; then
    log_info "Initializing template registry with default templates"
    
    # Copy default templates
    cp -r "$DEFAULT_TEMPLATES_DIR"/* "$TEMPLATES_DIR"
    
    log_success "Initialized template registry with default templates"
  fi

  return 0
}

# List all available templates
list_templates() {
  log_info "Available templates:"
  
  # Find all .dsl files in the templates directory
  local count=0
  local templates=()
  
  while IFS= read -r -d '' template; do
    # Get relative path from templates directory
    local rel_path="${template#$TEMPLATES_DIR/}"
    # Remove .dsl extension
    local template_name="${rel_path%.dsl}"
    templates+=("$template_name")
    ((count++))
  done < <(find "$TEMPLATES_DIR" -name "*.dsl" -type f -print0 | sort -z)
  
  # Print templates in columns with descriptions
  if [[ ${#templates[@]} -eq 0 ]]; then
    echo "No templates found."
    return 0
  fi
  
  # Print templates in a nice format
  printf "%-30s %-50s\n" "NAME" "DESCRIPTION"
  echo "----------------------------------------------------------------------"
  
  for template in "${templates[@]}"; do
    local description=""
    local template_file="${TEMPLATES_DIR}/${template}.dsl"
    
    # Extract description from first comment line
    if [[ -f "$template_file" ]]; then
      description=$(head -n 5 "$template_file" | grep -E '^#' | head -n 1 | sed 's/^#\s*//')
      # Truncate description if too long
      if [[ ${#description} -gt 50 ]]; then
        description="${description:0:47}..."
      fi
    fi
    
    printf "%-30s %-50s\n" "$template" "$description"
  done
  
  echo
  log_info "Found $count templates"
  
  return 0
}

# Show content of a template
show_template() {
  local template_name="$1"
  local template_file="${TEMPLATES_DIR}/${template_name}.dsl"
  
  if [[ ! -f "$template_file" ]]; then
    log_error "Template not found: $template_name"
    return 1
  fi
  
  log_info "Template: $template_name"
  echo "-------------------------------------------------------"
  
  # Show template content
  cat "$template_file"
  
  echo "-------------------------------------------------------"
  
  # Extract variables from template for help
  local variables=()
  while IFS= read -r line; do
    # Match {{VARIABLE}} patterns
    local vars=$(echo "$line" | grep -o '{{[A-Za-z0-9_]\+}}' | sed 's/{{//g' | sed 's/}}//g')
    if [[ -n "$vars" ]]; then
      for var in $vars; do
        # Add to array if not already present
        if [[ ! " ${variables[*]} " =~ " ${var} " ]]; then
          variables+=("$var")
        fi
      done
    fi
  done < "$template_file"
  
  # Show variable info if found
  if [[ ${#variables[@]} -gt 0 ]]; then
    echo
    log_info "Template variables:"
    for var in "${variables[@]}"; do
      echo "  - $var"
    done
  fi
  
  return 0
}

# Add a new template
add_template() {
  local source_path="$1"
  local template_name="$2"
  local target_file="${TEMPLATES_DIR}/${template_name}.dsl"
  
  if [[ ! -f "$source_path" ]]; then
    log_error "Source file not found: $source_path"
    return 1
  fi
  
  # Create target directory if needed
  mkdir -p "$(dirname "$target_file")"
  
  # Check if template already exists
  if [[ -f "$target_file" && "$FORCE" != true ]]; then
    log_error "Template already exists: $template_name"
    log_error "Use --force to overwrite"
    return 1
  fi
  
  # Copy template file
  cp "$source_path" "$target_file"
  
  log_success "Added template: $template_name"
  
  return 0
}

# Remove a template
remove_template() {
  local template_name="$1"
  local template_file="${TEMPLATES_DIR}/${template_name}.dsl"
  
  if [[ ! -f "$template_file" ]]; then
    log_error "Template not found: $template_name"
    return 1
  fi
  
  # Ask for confirmation unless force is enabled
  if [[ "$FORCE" != true ]]; then
    read -r -p "Are you sure you want to remove template '$template_name'? [y/N] " response
    if [[ ! "${response,,}" =~ ^y(es)?$ ]]; then
      log_info "Template removal cancelled"
      return 0
    fi
  fi
  
  # Remove the template
  rm "$template_file"
  
  log_success "Removed template: $template_name"
  
  return 0
}

# Apply a template with variable substitution
apply_template() {
  local template_name="$1"
  local output_file="$2"
  local template_file="${TEMPLATES_DIR}/${template_name}.dsl"
  
  if [[ ! -f "$template_file" ]]; then
    log_error "Template not found: $template_name"
    return 1
  fi
  
  # If no output file specified, generate one
  if [[ -z "$output_file" ]]; then
    # Get proposal ID from state for naming
    local proposal_id
    proposal_id=$(node_state get lastProposalId 2>/dev/null)
    
    # Increment proposal ID or use default
    if [[ -z "$proposal_id" || "$proposal_id" == "null" ]]; then
      proposal_id=1
    else
      proposal_id=$((proposal_id + 1))
    fi
    
    # Update proposal ID in state
    node_state set lastProposalId "$proposal_id"
    
    # Create output filename
    local template_basename=$(basename "$template_name")
    output_file="${QUEUE_DIR}/proposal_${proposal_id}_pending.dsl"
  fi
  
  # Check if output file already exists
  if [[ -f "$output_file" && "$FORCE" != true ]]; then
    log_error "Output file already exists: $output_file"
    log_error "Use --force to overwrite"
    return 1
  fi
  
  # Create output directory if needed
  mkdir -p "$(dirname "$output_file")"
  
  # Read template file
  local template_content
  template_content=$(cat "$template_file")
  
  # Extract variables from template
  local variables=()
  while IFS= read -r line; do
    # Match {{VARIABLE}} patterns
    local vars=$(echo "$line" | grep -o '{{[A-Za-z0-9_]\+}}' | sed 's/{{//g' | sed 's/}}//g')
    if [[ -n "$vars" ]]; then
      for var in $vars; do
        # Add to array if not already present
        if [[ ! " ${variables[*]} " =~ " ${var} " ]]; then
          variables+=("$var")
        fi
      done
    fi
  done < "$template_file"
  
  # Process each custom variable
  declare -A var_values
  for custom_var in "${CUSTOM_VARS[@]}"; do
    # Split KEY=VALUE
    IFS='=' read -r key value <<< "$custom_var"
    var_values["$key"]="$value"
  done
  
  # Ask for values of variables not provided
  for var in "${variables[@]}"; do
    if [[ -z "${var_values[$var]:-}" ]]; then
      read -r -p "Enter value for $var: " value
      var_values["$var"]="$value"
    fi
  done
  
  # Apply substitutions
  local output_content="$template_content"
  for var in "${!var_values[@]}"; do
    local value="${var_values[$var]}"
    # Escape special characters in value for sed
    value="${value//\\/\\\\}"
    value="${value//&/\\&}"
    value="${value//\//\\/}"
    
    # Substitute variable
    output_content=$(echo "$output_content" | sed "s/{{$var}}/$value/g")
  done
  
  # Write to output file
  echo "$output_content" > "$output_file"
  
  log_success "Applied template to: $output_file"
  
  return 0
}

main() {
  parse_args "$@"
  
  if ! validate_args; then
    exit 1
  fi
  
  # Initialize templates if needed
  initialize_templates
  
  # Execute the requested command
  if [[ "$LIST_ONLY" == true ]]; then
    list_templates
  elif [[ "$SHOW_CONTENT" == true ]]; then
    show_template "$TEMPLATE_NAME"
  elif [[ "$APPLY_TEMPLATE" == true ]]; then
    apply_template "$TEMPLATE_NAME" "$TEMPLATE_OUTPUT"
  elif [[ "$TEMPLATE_NAME" != "" && "$TEMPLATE_OUTPUT" != "" ]]; then
    # Add template command
    add_template "$TEMPLATE_OUTPUT" "$TEMPLATE_NAME"
  else
    # Remove template command
    remove_template "$TEMPLATE_NAME"
  fi
  
  exit 0
}

main "$@" 