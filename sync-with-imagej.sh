#!/bin/sh

URL=git://github.com/fiji/ImageJA
BRANCH=refs/heads/master
IJ1BRANCH=refs/heads/imagej

die () {
	echo "$*" >&2
	exit 1
}

NEED_TO_UPDATE_WORKING_TREE=
test $(git config --bool core.bare) = true ||
test $BRANCH != "$(git symbolic-ref HEAD 2> /dev/null)" || {
	git update-index -q --refresh &&
        git diff-files --quiet ||
	die "The work tree is dirty"
	NEED_TO_UPDATE_WORKING_TREE=t
}

ERROR="$(git fetch $URL $BRANCH 2>&1)" ||
die "${ERROR}No branch $BRANCH at $URL?"

HEAD=$(git rev-parse $BRANCH) || {
	HEAD=$(git rev-parse FETCH_HEAD) &&
	git update-ref -m "Initialize synchronization" $BRANCH $HEAD
} ||
die "Could not initialize $BRANCH"

if test -z "$NEED_TO_UPDATE_WORKING_TREE"
then
	git push . FETCH_HEAD:$BRANCH ||
	die "Could not pull $BRANCH"
	HEAD=$(git rev-parse $BRANCH) ||
	die "Could not parse $BRANCH"
else
	test $HEAD = $(git rev-parse FETCH_HEAD) ||
	die "Branch $BRANCH is not up-to-date!"
fi

IJ1HEAD=$(git rev-parse $IJ1BRANCH) ||
die "No ImageJ1 branch?"

test $IJ1HEAD != "$(git merge-base $IJ1HEAD $HEAD)" ||
die "ImageJ1 already fully merged!"

VERSION="$(git log -1 --pretty=format:%s $IJ1HEAD |
	sed -n "s/^[^0-9]*\([^ 0-9A-Za-z] \)\?\([1-9][\\.0-9]*.\)[^0-9A-Za-z].*$/\2/p")" ||
die "Could not determine ImageJ version from branch $IJ1BRANCH"

# write an update without checking anything out
export GIT_INDEX_FILE="$(git rev-parse --git-dir)"/IJ1INDEX &&
git read-tree $IJ1HEAD ||
die "Could not read current ImageJ1 tree"

# rewrite version in pom.xml
git show $HEAD:pom.xml > "$GIT_INDEX_FILE.pom" &&
sed '/^\t</s/\(<version>\).*\(<\/version>\)/\1'"$VERSION"'\2/' \
	< "$GIT_INDEX_FILE.pom" > "$GIT_INDEX_FILE.pom.new" &&
POMHASH=$(git hash-object -w "$GIT_INDEX_FILE.pom.new") &&
printf "100644 $POMHASH 0\tpom.xml\n" > "$GIT_INDEX_FILE.list.new" ||
die "Could not update pom.xml"

# copy .gitignore from previous HEAD
GITIGNORE=$(git rev-parse $HEAD:.gitignore 2>/dev/null) &&
printf "100644 $GITIGNORE 0\t.gitignore\n" >> "$GIT_INDEX_FILE.list.new" ||
die "Could not find .gitignore in the current HEAD"

git ls-files --stage > "$GIT_INDEX_FILE.list.old" &&
mv "$GIT_INDEX_FILE" "$GIT_INDEX_FILE.old" &&
sed -e 's~\t\(.*\.java\)$~\tsrc/main/java/\1~' \
	-e 's~\tplugins/\(.*\)\.source$~\tsrc/main/java/\1.java~' \
	-e 's~\t\(IJ_Props.txt\|macros/\)~\tsrc/main/resources/\1~' \
	-e 's~\timages/~\tsrc/main/resources/~' \
	-e 's~\t\(MANIFEST.MF\)$~\tsrc/main/resources/META-INF/\1~' \
	-e '/\t\(plugins\/.*\.class\|.FBCIndex\|ij\/plugin\/RandomOvals.txt\)$/d' \
< "$GIT_INDEX_FILE.list.old" >> "$GIT_INDEX_FILE.list.new" &&
git update-index --index-info  < "$GIT_INDEX_FILE.list.new" ||
die "Could not transform $IJ1BRANCH's tree"

echo "Synchronize with ImageJ $VERSION" > "$GIT_INDEX_FILE.message" &&
TREE=$(git write-tree) &&
NEWHEAD="$(git commit-tree $TREE -p $HEAD -p $IJ1HEAD \
	< "$GIT_INDEX_FILE.message")" &&
git update-ref -m "Synchronize with ImageJ1" $BRANCH $NEWHEAD $HEAD ||
die "Could not update $BRANCH"

test -z "$NEED_TO_UPDATE_WORKING_TREE" || {
	echo "Updating work-tree" &&
	unset GIT_INDEX_FILE &&
	git stash
} ||
die "Could not update the working tree"