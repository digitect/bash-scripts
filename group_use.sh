# Script to set group use for a directory
# Replace <linux-user>, <linux-group> and <directory> and run.
USER=<linux-user>
GROUP=<linux-group>
DIR=<directory>
chown -R $USER:$GROUP $DIR
find $DIR -exec chmod g+u {} \;
find $DIR -exec chmod o-rwx {} \;
find $DIR -type d -exec chmod g+s {} \;
