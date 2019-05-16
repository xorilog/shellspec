#!/bin/sh
#shellcheck disable=SC2004,SC2016

set -eu

echo $$ > "$SHELLSPEC_TMPBASE/reporter_pid"

: "${SHELLSPEC_SPEC_FAILURE_CODE:=101}"

# shellcheck source=lib/libexec/reporter.sh
. "${SHELLSPEC_LIB:-./lib}/libexec/reporter.sh"
use import reset_params each replace

interrupt='' aborted=1 no_examples=''
if (trap - INT) 2>/dev/null; then trap 'interrupt=1' INT; fi
if (trap - TERM) 2>/dev/null; then trap '' TERM; fi

import "color_schema"
color_constants "${SHELLSPEC_COLOR:-}"

: "${SHELLSPEC_FORMATTER:=debug}"

import "${SHELLSPEC_FORMATTER}_formatter"
"${SHELLSPEC_FORMATTER##*/}_formatter" "$@"

parse_lines() {
  buf=''
  while IFS= read -r line || [ "$line" ]; do
    [ "$fail_fast" ] && break
    case $line in
      $RS*) [ -z "$buf" ] || parse_fields "$buf"; buf=${line#?} ;;
      *) buf="$buf${buf:+$LF}${line}" ;;
    esac
  done
  [ -z "$buf" ] || parse_fields "$buf"
}

parse_fields() {
  reset_params '$1' "$US"
  eval "$RESET_PARAMS"

  for field in "$@"; do
    eval "field_${field%%:*}=\${field#*:}"
    set -- "$@" "${field%%:*}"
    shift
  done

  each_line "$@"
}

exit_status=0 found_focus=''
fail_fast='' fail_fast_count=${SHELLSPEC_FAIL_FAST_COUNT:-}

invoke_formatters begin
"${SHELLSPEC_FORMATTER}_output" begin

# shellcheck disable=SC2034
{
  current_example_index=0 example_index='' detail_index=0
  last_block_no='' last_skip_id='' not_enough_examples=''
  field_type='' field_tag='' field_block_no='' field_focused=''
  field_conditional='' field_skipid='' field_pending=''
  example_count=0 succeeded_count='' failed_count='' warned_count=''
  todo_count='' fixed_count='' skipped_count='' suppressed_skipped_count=''
}

each_line() {
  case $field_type in
    begin) last_block_no=0 last_skip_id=''
      # shellcheck disable=SC2034
      {
        example_count_per_file=0 succeeded_count_per_file=0
        failed_count_per_file=0 warned_count_per_file=0 todo_count_per_file=0
        fixed_count_per_file=0 skipped_count_per_file=0
      }
      ;;
    example)
      if [ "$field_block_no" -le "$last_block_no" ]; then
        abort "Illegal executed the same block in ${field_specfile:-}" \
          "line ${field_range:-}${LF}(e.g. do not include blocks in a loop)"
      fi
      [ "$field_focused" = "focus" ] && found_focus=1
      example_index='' last_block_no=$field_block_no
      ;;
    statement)
      while :; do
        # Do not add references if example_index is blank
        case $field_tag in
          evaluation) break ;;
          good) [ "$field_pending" ] || break ;;
          skip)
            case $SHELLSPEC_SKIP_MESSAGE in (quiet)
              [ ! "$field_conditional" ] || break
            esac
            case $SHELLSPEC_SKIP_MESSAGE in (moderate|quiet)
                [ "$field_skipid" = "$last_skip_id" ] && break
                last_skip_id=$field_skipid
            esac
        esac

        if [ "$example_index" ]; then
          detail_index=$(($detail_index + 1))
        else
          current_example_index=$(($current_example_index + 1)) detail_index=1
          example_index=$current_example_index
        fi
        break
      done
      ;;
    result)
      example_count=$(($example_count + 1))
      example_count_per_file=$(($example_count_per_file + 1))
      eval "${field_tag}_count=\$((\$${field_tag}_count + 1))"
      eval "${field_tag}_count_per_file=\$((\$${field_tag}_count_per_file + 1))"
      [ "${field_error:-}" ] && exit_status=$SHELLSPEC_SPEC_FAILURE_CODE
      if [ "${failed_count:-0}" -ge "${fail_fast_count:-999999}" ]; then
        aborted='' fail_fast=1
      fi
      if [ "$field_tag" = "skipped" ] && [ -z "$example_index" ]; then
        suppressed_skipped_count=$(($suppressed_skipped_count + 1))
      fi
      ;;
    end)
      # field_example_count not provided with range or filter
      : "${field_example_count:=$example_count_per_file}"
      if [ "$example_count_per_file" -ne "$field_example_count" ]; then
        not_enough_examples=1
      fi
      ;;
    finished) aborted=''
  esac

  color_schema
  invoke_formatters format "$@"
  "${SHELLSPEC_FORMATTER}_output" format
}
parse_lines

if [ "$aborted" ]; then
  exit_status=1
elif [ "$interrupt" ]; then
  exit_status=130
elif [ "${SHELLSPEC_FAIL_NO_EXAMPLES:-}" ] && [ "$example_count" -eq 0 ]; then
  #shellcheck disable=SC2034
  no_examples=1 exit_status=$SHELLSPEC_SPEC_FAILURE_CODE
elif [ "$not_enough_examples" ]; then
  exit_status=$SHELLSPEC_SPEC_FAILURE_CODE
fi

callback() { [ -e "$SHELLSPEC_TIME_LOG" ] || sleep 0; }
shellspec_sequence callback 1 10
read_time_log "time" "$SHELLSPEC_TIME_LOG"

invoke_formatters end
"${SHELLSPEC_FORMATTER}_output" end

if [ "$found_focus" ] && [ ! "${SHELLSPEC_FOCUS_FILTER:-}" ]; then
  info "You need to specify --focus option to run focused (underlined) example(s) only.$LF"
fi

exit "$exit_status"
