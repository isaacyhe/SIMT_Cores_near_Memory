# Validates signoff.tsv (run as: awk -F'\t' -f signoff_check.awk signoff.tsv; exit 1 = malformed). Every reader runs it first.
# Rows: layout (no blanks), period in ps on the user clock grid, odb file name (*.odb, no blanks or CR), evidence. Unique layouts.
BEGIN { grid["2000"]; grid["2500"]; grid["3000"]; grid["4000"]; grid["5000"]; grid["6000"]; grid["10000"] }
/\r/ { print "signoff.tsv: CR in line " NR > "/dev/stderr"; bad = 1; next }
/^#/ || $1 == "layout" { next }
{
  if (NF < 3 || $1 !~ /^[A-Za-z0-9_]+$/ || !($2 in grid) || $3 !~ /^[A-Za-z0-9_.]+\.odb$/ || seen[$1]++) {
    print "signoff.tsv: malformed line " NR ": " $0 > "/dev/stderr"; bad = 1 }
}
END { exit bad }
