#!/bin/bash
set -e

# Users
# (no password login is possible, see ssh)
# (authorized keys must be set up manually
# and will be contained in backup)
############################################

# create user chris
useradd -m -d /home/chris -s /bin/bash chris

# prepare ssh authorized keys
mkdir -p /home/chris/.ssh
touch /home/chris/.ssh/authorized_keys
chmod 700 /home/chris/.ssh
chmod 600 /home/chris/.ssh/authorized_keys

# add to sudoers
echo "chris ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# create user backupconsumer
useradd -m -d /home/backupconsumer -s /bin/bash backupconsumer

# prepare ssh authorized keys
mkdir -p /home/backupconsumer/.ssh
touch /home/backupconsumer/.ssh/authorized_keys
chmod 700 /home/backupconsumer/.ssh
chmod 600 /home/backupconsumer/.ssh/authorized_keys

# create user github-deployer
useradd -m -d /home/github-deployer -s /bin/bash github-deployer

# prepare ssh authorized keys
mkdir -p /home/github-deployer/.ssh
touch /home/github-deployer/.ssh/authorized_keys
chmod 700 /home/github-deployer/.ssh
chmod 600 /home/github-deployer/.ssh/authorized_keys

# SSH
############################################

# disable password login, except root
# 'EOF' disables parameter expansion
cat >> /etc/ssh/sshd_config <<'EOF'

# disable password login for all but root
PasswordAuthentication no
Match User root
PasswordAuthentication yes
Match all
EOF

# login delay
# -e enabled backslash escapes (so newlines are put into file instead of \n as text)
echo -e "\n# add delay for failed logins\nauth       optional   pam_faildelay.so  delay=10000000" >> /etc/pam.d/common-auth

# login slack notify
# 'EOF' disables parameter expansion
cat > /etc/ssh/sshrc <<'EOF'
#!/bin/bash
set -e

# get IP
IP=$(echo "$SSH_CONNECTION" | cut -d " " -f 1)

# message configuration
SERVICE="sshd"
TEXT="Contabo Cloud VPS 1: $USER logged in ($IP)"

# slack configuration
WEBHOOK=https://hooks.slack.com/services/REPLACE/ME

# post to slack webhook
if [ "$USER" != "git" ]; then
  curl -sX POST --data-urlencode "payload={\"channel\": \"#contabo-vps\", \"username\": \"$SERVICE\", \"text\": \"$TEXT\", \"icon_emoji\": \":ghost:\"}" $WEBHOOK > /dev/null
fi
EOF

# restart service
service sshd restart

# Reset crontab
############################################
echo "" | crontab
echo "Crontab initialized:"
crontab -l

# Backup
############################################
mkdir -p /root/scripts/
# 'EOF' disables parameter expansion
cat > /root/scripts/backup.sh <<'EOF'
#!/bin/bash
set -e

# variables
DIR=/home/backupconsumer/backup
WORK_DIR=$DIR/work
LOG=$DIR/backup.log

# goto backup user home
cd /home/backupconsumer/

# ensure backup dir
if [ ! -d "$DIR" ]; then
  mkdir $DIR
  chown -R backupconsumer $DIR
fi

# goto backup dir
cd $DIR

# remove log
if [ -f "$LOG" ]; then
  rm -f $LOG
fi

# create or clean work dir
if [ -d "$WORK_DIR" ]; then
  echo "$(date) cleaning work dir" >> $LOG
  rm -rf $WORK_DIR/*
else
  echo "$(date) creating work dir" >> $LOG
  mkdir $WORK_DIR
  chown -R backupconsumer $WORK_DIR
fi

# copy home directories data
echo "$(date) copying home directories data" >> $LOG
mkdir -p $WORK_DIR/home/chris/.ssh
cp -rd /home/chris/.ssh $WORK_DIR/home/chris/
cp -rd /home/chris/.toprc $WORK_DIR/home/chris/.toprc
mkdir -p $WORK_DIR/home/backupconsumer/.ssh
cp -rd /home/backupconsumer/.ssh $WORK_DIR/home/backupconsumer/
mkdir -p $WORK_DIR/home/github-deployer/.ssh
cp -rd /home/github-deployer/.ssh $WORK_DIR/home/github-deployer/

# copy docker data and configs
echo "$(date) copying docker data and configs" >> $LOG
#mkdir -p $WORK_DIR/etc/docker
#cp -r /etc/docker/* $WORK_DIR/etc/docker/
mkdir -p $WORK_DIR/var/docker
cp -r /var/docker/data $WORK_DIR/var/docker/

# archive contents
echo "$(date) compressing" >> $LOG
cd $WORK_DIR
tar -zpcf $DIR/"backup-$(date +"%Y-%m").tar.gz" .
cd $DIR

# delete work dir
echo "$(date) deleting work dir" >> $LOG
rm -rf $WORK_DIR

# chown archive file
chown -R backupconsumer $DIR

# done
echo "$(date) done." >> $LOG
EOF
chmod +x /root/scripts/backup.sh
(crontab -l ; echo "0 4 * * * /root/scripts/backup.sh") | crontab

echo "Crontab updated:"
crontab -l

# Firewall
############################################

ufw allow 22/tcp
ufw allow 22/udp
ufw allow 80/tcp
ufw allow 80/udp
ufw allow 443/tcp
ufw allow 443/udp
echo "y" | ufw enable
ufw status numbered

# Docker
############################################

# install docker: https://docs.docker.com/install/linux/docker-ce/ubuntu/
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo apt-key fingerprint 0EBFCD88
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# init docker swarm
# use following commands to obtain the join token, if joining new nodes
# sudo docker swarm join-token manager
# sudo docker swarm join-token worker
docker swarm init

# test if docker is fine
docker run hello-world

# prepare global router network
docker network create -d overlay global_router

# prepare docker storage
mkdir -p /var/docker
mkdir -p /var/docker/data
mkdir -p /var/docker/data-no-backup

# add chris to docker group
usermod -a -G docker chris
usermod -a -G docker github-deployer
