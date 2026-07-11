# classify.awk — three-state classifier for one AI-CLI pane's footer text.
#
# Input : ENVIRON["AISTATUS_CMD"]  = pane_current_command (lowercased inside)
#         ENVIRON["AISTATUS_TITLE"] = pane_title (OSC title, may carry a spinner)
#         screen text (the pane footer, ~last 30 lines) on stdin.
# Output: one word on stdout — BUSY | WAIT | IDLE — or an empty line for
#         "not an agent / neutral / unknown". status.sh collapses these:
#           BUSY -> busy   (burning tokens)
#           WAIT -> blocked (stuck on a permission prompt / menu — needs a human)
#           IDLE -> idle    (empty prompt, waiting for the next instruction)
#
# WHY byte-wise matching: tmux runs status `#()` commands with a minimal env
# (HOME="", LANG unset => C locale). Under C locale awk's index()/substr()
# operate byte-by-byte, so the multibyte glyphs this classifier keys on
# (❯ ─ │ ✳ braille) are written as UTF-8 octal-byte literals and compared as
# raw bytes. Callers MUST invoke this with LC_ALL=C (see status.sh) so the
# same byte-wise behavior holds on macOS awk regardless of the outer locale.
#
# WHY region convergence + NOT-gates (the anti-pollution design, kept verbatim
# in spirit from the private source): a naive "grep the whole screen for a
# spinner / 'esc to interrupt'" lights the capsule up on *scrollback* — e.g. an
# example transcript quoting a running agent. Every "working" signal here is
# anchored to the bottom-N non-empty lines (BOTTOMWORK / B5 / B6), the OSC
# title, or the composer box (find_box). The NOT-gates (empty-❯ veto, box
# present => idle, bottom-zone live-working veto) stop a live-looking artifact
# higher up the buffer from being read as the current state. Do not "simplify"
# this back to a whole-screen bare match — that regression is exactly the
# 2026-07-04 false-positive it was built to prevent.
#
# ponytail: two "skip" rules from the origin ruleset (transcript_viewer /
# model_picker) are not ported — both yield neither state and no lower-priority
# rule mis-fires on them across the fixtures. Upgrade trigger: a real case where
# a skip screen leaves a spinner in the bottom-5 and mis-reads as BUSY.

function trim(s){sub(/^[ \t]+/,"",s);sub(/[ \t]+$/,"",s);return s}
function has_spinner(s){return(index(s,"\342\234\263")||index(s,"\342\234\266")||index(s,"\342\234\270")||index(s,"\342\234\273")||index(s,"\342\234\275")||index(s,"\342\234\264")||index(s,"\342\234\242")||index(s,"\342\234\267"))}
function has_braille(s){return(index(s,"\342\240")||index(s,"\342\241")||index(s,"\342\242")||index(s,"\342\243"))}
function braille_prefix(s,   c1,c2,c4){c1=substr(s,1,1);c2=substr(s,2,1);c4=substr(s,4,1);return(c1=="\342"&&(c2=="\240"||c2=="\241"||c2=="\242"||c2=="\243")&&c4==" ")}
function star_idle(s){return(substr(s,1,4)=="\342\234\263 ")}
function is_rule(s,   t,i,rc,rest){t=trim(s);if(t=="")return 0;rc=0;i=1;while(substr(t,i,3)==RULE){rc++;i+=3}if(rc==0)return 0;rest=substr(t,i);sub(/^[ \t]+/,"",rest);return(rest==""||rc>=3)}
function prompt_line(s,   t,c){t=s;while(1){c=substr(t,1,1);if(c==" "||c=="\t"){t=substr(t,2);continue}if(substr(t,1,3)==BAR){t=substr(t,4);continue}break}return(substr(t,1,3)==ARROW)}
function select_cursor(s,   t){t=s;sub(/^[ \t]+/,"",t);if(substr(t,1,3)!=ARROW)return 0;t=substr(t,4);if(!(substr(t,1,1)==" "||substr(t,1,1)=="\t"))return 0;sub(/^[ \t]+/,"",t);return(t!="")}
function yesno(s,   t,c){t=s;sub(/^[ \t]+/,"",t);if(substr(t,1,3)==ARROW){t=substr(t,4);sub(/^[ \t]+/,"",t)}c=substr(t,1,1);if(!(c=="1"||c=="2"||c=="3"))return 0;t=substr(t,2);if(substr(t,1,1)!=".")return 0;t=substr(t,2);sub(/^[ \t]+/,"",t);t=tolower(t);return(substr(t,1,3)=="yes"||substr(t,1,2)=="no")}
function choice_cursor(s,   p,t){p=index(s,ARROW);if(p==0)return 0;t=substr(s,p+3);sub(/^[ \t]*/,"",t);return(t~/^[0-9]+\./)}
function empty_prompt(s,   t){t=s;sub(/^[ \t]+/,"",t);if(substr(t,1,3)!=ARROW)return 0;t=substr(t,4);gsub(/[ \t]/,"",t);gsub(/\302\240/,"",t);return(t=="")}
function jointext(a,b,   i,s){s="";if(a<1)return s;for(i=a;i<=b;i++){s=s lines[i];if(i<b)s=s "\n"}return s}
function bstart(N,   i,c){if(n<1)return 0;c=0;for(i=n;i>=1;i--){if(trim(lines[i])!=""){c++;if(c==N)return i}}for(i=1;i<=n;i++)if(trim(lines[i])!="")return i;return 0}
function region_has(a,b,needle){if(a<1)return 0;return index(tolower(jointext(a,b)),needle)}
function any_prompt(a,b,   i){if(a<1)return 0;for(i=a;i<=b;i++)if(prompt_line(lines[i]))return 1;return 0}
function any_select(a,b,   i){if(a<1)return 0;for(i=a;i<=b;i++)if(select_cursor(lines[i]))return 1;return 0}
function any_yesno(a,b,   i){if(a<1)return 0;for(i=a;i<=b;i++)if(yesno(lines[i]))return 1;return 0}
function any_choice(a,b,   i){if(a<1)return 0;for(i=a;i<=b;i++)if(choice_cursor(lines[i]))return 1;return 0}
function any_empty(a,b,   i){if(a<1)return 0;for(i=a;i<=b;i++)if(empty_prompt(lines[i]))return 1;return 0}
function after_rule(   i,last){last=-1;for(i=1;i<=n;i++)if(is_rule(lines[i]))last=i;if(last<0)return 1;return last+1}
function find_box(   i,trailing){boxOk=0;boxBottom=-1;trailing=0;for(i=n;i>=1;i--){if(is_rule(lines[i])){boxBottom=i;break}if(trim(lines[i])!=""){trailing++;if(trailing>4)return}}if(boxBottom<0)return;boxTop=-1;for(i=boxBottom-1;i>=1;i--){if(is_rule(lines[i])){boxTop=i;break}}if(boxTop<0)return;for(i=boxTop+1;i<boxBottom;i++){if(trim(lines[i])=="")continue;if(prompt_line(lines[i])){boxOk=1;return}return}}
function interrupt_outside(   i,seen){for(i=boxBottom+1;i<=n;i++)if(index(tolower(lines[i]),"esc to interrupt"))return 1;seen=0;for(i=boxTop-1;i>=1&&seen<2;i--){if(trim(lines[i])=="")continue;seen++;if(index(tolower(lines[i]),"esc to interrupt"))return 1}return 0}
function idlenotgate(a,b){return(region_has(a,b,"enter to select")||region_has(a,b,"esc to cancel")||region_has(a,b,"tab/arrow keys")||region_has(a,b,"arrow keys to navigate")||region_has(a,b,"\342\206\221/\342\206\223 to navigate")||region_has(a,b,"do you want to")||region_has(a,b,"would you like to")||region_has(a,b,"esc to interrupt"))}
function bashsig(){return(index(WHOLE_LC,"bash command")||index(WHOLE_LC,"bash(")||index(WHOLE_LC,"contains expansion")||index(WHOLE_LC,"tab to amend")||index(WHOLE_LC,"ctrl+e to explain"))}
function permq(a,b){return(region_has(a,b,"do you want to proceed?")||region_has(a,b,"do you want to make this edit")||region_has(a,b,"do you want to create")||region_has(a,b,"would you like to proceed?"))}
function legacy(   hasyc){if(boxOk)return 0;if(BOTTOMWORK)return 0;hasyc=(index(WHOLE_LC,"yes")||index(WHOLE,ARROW));if(!((index(WHOLE_LC,"do you want to")&&hasyc)||(index(WHOLE_LC,"would you like to")&&hasyc)||index(WHOLE_LC,"waiting for permission")||index(WHOLE_LC,"do you want to allow this connection?")||index(WHOLE_LC,"tab to amend")||index(WHOLE_LC,"ctrl+e to explain")||(index(WHOLE_LC,"do you want to proceed?")&&index(WHOLE_LC,"esc to cancel"))||index(WHOLE_LC,"review your answers")||index(WHOLE_LC,"skip interview and plan immediately")))return 0;return(!any_empty(1,n))}
function claude_rules(   ar){
  if(braille_prefix(TITLE))return "BUSY"
  if(!boxOk&&!BOTTOMWORK&&region_has(B12,n,"enter to select")&&any_select(1,n))return "WAIT"
  if(index(WHOLE_LC,"run a dynamic workflow?")&&index(WHOLE_LC,"esc to cancel"))return "WAIT"
  if(boxOk){if(!interrupt_outside())return "IDLE"}
  else{if(any_prompt(B6,n)&&!idlenotgate(B6,n)&&!any_choice(B6,n))return "IDLE"}
  if(!BOTTOMWORK&&index(WHOLE_LC,"do you want to proceed?")&&bashsig()&&any_yesno(1,n))return "WAIT"
  ar=after_rule();if(!BOTTOMWORK&&permq(ar,n)&&any_yesno(ar,n))return "WAIT"
  if(legacy())return "WAIT"
  if(region_has(B5,n,"esc to interrupt")||region_has(B5,n,"thinking")||region_has(B5,n,"processing")||has_spinner(jointext(B5,n)))return "BUSY"
  if(star_idle(TITLE))return "IDLE"
  return ""
}
function codex_rules(){
  if(index(tolower(TITLE),"action required"))return "WAIT"
  if(braille_prefix(TITLE))return "BUSY"
  if(index(WHOLE_LC,"press enter to confirm or esc to cancel")||index(WHOLE_LC,"allow command?")||index(WHOLE_LC,"enter to submit answer")||index(WHOLE_LC,"enter to submit all"))return "WAIT"
  if(!(region_has(B6,n,"esc to interrupt")||has_braille(jointext(B6,n)))){if(index(WHOLE_LC,"[y/n]")||index(WHOLE_LC,"yes (y)")||(index(WHOLE_LC,"do you want to")&&(index(WHOLE_LC,"yes")||index(WHOLE,ARROW))))return "WAIT"}
  if(region_has(B6,n,"esc to interrupt")||has_braille(jointext(B6,n)))return "BUSY"
  return ""
}
function generic_rules(){if(braille_prefix(TITLE))return "BUSY";return ""}
function generic_agent_rules(){if(braille_prefix(TITLE))return "BUSY";if(star_idle(TITLE))return "IDLE";return ""}
BEGIN{
  RULE="\342\224\200";ARROW="\342\235\257";BAR="\342\224\202"
  split("claude claude-code codex gemini aider cursor cursor-agent agy copilot opencode amp droid qwen kimi hermes pi",TMP," ")
  for(k in TMP)AG[TMP[k]]=1
}
{lines[NR]=$0}
END{
  n=NR
  TITLE=ENVIRON["AISTATUS_TITLE"];CMD=tolower(ENVIRON["AISTATUS_CMD"])
  WHOLE=jointext(1,n);WHOLE_LC=tolower(WHOLE)
  B5=bstart(5);B6=bstart(6);B12=bstart(12)
  BOTTOMWORK=(region_has(B5,n,"esc to interrupt")||has_spinner(jointext(B5,n)))
  find_box()
  if(CMD=="node"||CMD=="bun"||CMD=="deno"){print generic_rules();exit}
  isagent=(CMD in AG)||(CMD ~ /^[0-9]+\.[0-9]+\.[0-9]+/)||(CMD ~ /^codex-/)
  if(!isagent){print "";exit}
  if(CMD=="codex"||CMD ~ /^codex-/){print codex_rules();exit}
  if(CMD=="claude"||CMD=="claude-code"||CMD ~ /^[0-9]+\.[0-9]+\.[0-9]+/){print claude_rules();exit}
  print generic_agent_rules()
}
