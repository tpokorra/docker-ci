#!/bin/sh

# verbose and exit on error
set -xe

# import GPG keys
gpg --import /gpg/nextcloud-bot.public.asc
gpg --allow-secret-key-import --import /gpg/nextcloud-bot.asc
gpg --list-keys

# fetch git repo
git clone git@github.com:nextcloud/server /app

# TODO use build/l10nParseAppInfo.php to fetch app names for l10n

versions='stable19 stable20 stable21 master'

# build POT files for all versions
mkdir stable-templates
for version in $versions
do
  # skip if the branch doesn't exist
  if git branch -r | egrep "^\W*origin/$version$" ; then
    echo "Valid branch"
  else
    echo "Invalid branch"
    continue
  fi

  git checkout $version

  # build POT files
  /translationtool.phar create-pot-files

  cd translationfiles/templates/
  for file in $(ls)
  do
    mv $file ../../stable-templates/$version.$file
  done
  cd ../..
done

# merge POT files into one
for file in $(ls stable-templates/master.*)
do
  name=$(echo $file | cut -b 25- )
  msgcat --use-first stable-templates/*.$name > translationfiles/templates/$name
done

# remove intermediate POT files
rm -rf stable-templates

# push sources
tx push -s

# pull translations - force pull because a fresh clone has newer time stamps
tx pull -f -a --minimum-perc=50
# pull all "lib" translations for the language name
tx pull -a -f -r nextcloud.lib --minimum-perc=0
# pull 20% of "settings" translations for the region name
tx pull -a -f -r nextcloud.settings-1 --minimum-perc=20

backportVersions='master stable21 stable20 stable19'
for version in $backportVersions
do
  # skip if the branch doesn't exist
  if git branch -r | egrep "^\W*origin/$version$" ; then
    echo "Valid branch"
  else
    echo "Invalid branch"
    continue
  fi

  git checkout $version

  # delete removed l10n files that are used for language detection (they will be recreated during the write)
  find core/l10n -type f -delete
  find lib/l10n -type f -delete

  # build JS/JSON based on translations
  /translationtool.phar convert-po-files

  # remove tests/
  rm -rf tests
  git checkout -- tests/

  # create git commit and push it
  git add apps core lib

  git commit -am "[tx-robot] updated from transifex" -s || true
  git push origin $version

  echo "done with $version"
done
