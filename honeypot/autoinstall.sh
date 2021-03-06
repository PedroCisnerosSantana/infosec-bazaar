#!/bin/bash

# Honeypot AutoInstall Script v0.6.0
# by Chris Campbell
#
# Twitter: @phage_nz
# GitHub: phage-nz
# Blog: https://phage.nz

# Installs:
# Dionaea and DionaeaFR
# p0f
# Cowrie
#
# Tested on Ubuntu 14.04.5 (EC2 t2.micro instance and DigitalOcean 1GB+1CPU droplet)

# Variables:
INSTALL_DIONAEA="yes" # yes or no.
INSTALL_DIONAEAFR="yes" # yes or no.
INSTALL_COWRIE="no" # yes or no.

SSL_C="US" # Country code.
SSL_CN="example.company.com" # Certificate CN.
SSL_O="Example Company Ltd."  # Company name.
SSL_OU="OU" # Organisational unit.

DOMAIN="WORKGROUP" # Domain name.
SERVER="EXAMPLE-SERVER" # Server name.

VT_KEY="" # Your VirusTotal API key.

HOST_NAME="" # Your host name (for DionaeaFR).

#
# SCRIPT START
#

# Install must be done as root.
if [ "$EUID" -ne 0 ]
  then echo "Please run as root!"
  exit 1
fi

# Install main dependencies.
if [ "$INSTALL_DIONAEA" == "yes" ] || [ "$INSTALL_COWRIE" == "yes" ] || [ "$INSTALL_DIONAEAFR" == "yes" ] ; then
  echo "Updating server..."
  apt update
  apt upgrade -y
  echo "Installing main dependencies..."
  apt install autoconf automake build-essential check git libssl-dev python-dev python-pip python-software-properties software-properties-common -y
  pip install --upgrade pip
else
  echo "Nothing to be installed."
  exit 0
fi

# Install services.
echo "Installing services..."

# Install Dionaea.
if [ "$INSTALL_DIONAEA" == "yes" ]; then
  echo "Installing Dionaea..."
  apt install software-properties-common
  add-apt-repository ppa:honeynet/nightly -y
  apt update
  apt install dionaea p0f -y
  echo "Making Dionaea honeypot database..."
  mkdir -p /opt/dionaea/var/dionaea/scripts
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/generate_user_db.py -P /opt/dionaea/var/dionaea/scripts
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/wordlist.txt -P /opt/dionaea/var/dionaea/scripts
  chown -R dionaea:dionaea /opt/dionaea/var/dionaea
  chmod +x /opt/dionaea/var/dionaea/scripts/generate_user_db.py
  touch /opt/dionaea/var/dionaea/target_db.sqlite
  python /opt/dionaea/var/dionaea/scripts/generate_user_db.py
  echo "Fixing up Dionaea config files..."
  sed -e '/errors.filename/ s/^#*/#/' -i /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -e '/errors.levels/ s/^#*/#/' -i /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -e '/errors.domains/ s/^#*/#/' -i /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(default.levels=\).*/\1all,-debug/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/# ssl.default/ssl.default/g' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(ssl.default.c=\).*/\1'"$SSL_C"'/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(ssl.default.cn=\).*/\1'"$SSL_CN"'/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(ssl.default.o=\).*/\1'"$SSL_O"'/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/^\(ssl.default.ou=\).*/\1'"$SSL_OU"'/' /opt/dionaea/etc/dionaea/dionaea.cfg
  sed -i 's/apikey: "........."/apikey: "'"$VT_KEY"'"/g' /opt/dionaea/etc/dionaea/ihandlers-available/virustotal.yaml
  sed -i 's/\/tmp/\/var\/run/g' /opt/dionaea/etc/dionaea/ihandlers-available/p0f.yaml
  sed -i '9,10 s/^#//' /opt/dionaea/etc/dionaea/services-available/mysql.yaml
  sed -i 's/\/path\/to\/cc_info.sqlite/\/opt\/dionaea\/var\/dionaea\/target_db.sqlite/g' /opt/dionaea/etc/dionaea/services-available/mysql.yaml
  sed -i '4,6 s/^#//' /opt/dionaea/etc/dionaea/services-available/pptp.yaml
  sed -e '/self.make_comment/ s/^#*/#/' -i /opt/dionaea/lib/dionaea/python/dionaea/virustotal.py
  sed -e '/self.root_path\s*=\s*/ s/^#*/#/' -i /opt/dionaea/lib/dionaea/python/dionaea/sip/extras.py
  sed -e '/self.users\s*=\s*/ s/^#*/#/' -i /opt/dionaea/lib/dionaea/python/dionaea/sip/extras.py
  sed -i 's/sqlite3.connect(self.users)/sqlite3.connect("\/opt\/dionaea\/var\/dionaea\/sipaccounts.sqlite")/g' /opt/dionaea/lib/dionaea/python/dionaea/sip/extras.py
  sed -i 's/"OemDomainName", "WORKGROUP"/"OemDomainName", "'"$DOMAIN"'"/g' /opt/dionaea/lib/dionaea/python/dionaea/smb/include/smbfields.py
  sed -i 's/"ServerName", "HOMEUSER-3AF6FE"/"ServerName", "'"$SERVER"'"/g' /opt/dionaea/lib/dionaea/python/dionaea/smb/include/smbfields.py
  sed -i  's/^\(\s*r\.VersionToken\.TokenType\s*=\s*\).*$/\10xAA/' /opt/dionaea/lib/dionaea/python/dionaea/mssql/mssql.py
  echo "Enabling VirusTotal handler..."
  ln -s /opt/dionaea/etc/dionaea/ihandlers-available/virustotal.yaml /opt/dionaea/etc/dionaea/ihandlers-enabled 
  echo "Enabling Dionaea p0f handler..."
  ln -s /opt/dionaea/etc/dionaea/ihandlers-available/p0f.yaml /opt/dionaea/etc/dionaea/ihandlers-enabled
  echo "Making a folder for SIP pcap's..."
  mkdir -p /opt/dionaea/var/dionaea/rtp/default
  echo "Making logrotate script..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/dionaea.logrotate -O /etc/logrotate.d/dionaea
  echo "Making housekeeper script..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/dionaea-housekeeper.sh -O /etc/cron.daily/dionaea-housekeeper
  chmod +x /etc/cron.daily/dionaea-housekeeper
  echo "Setting all services to autostart..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/dionaea.init -O /etc/init.d/dionaea
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/p0f.init -O /etc/init.d/p0f
  chmod +x /etc/init.d/dionaea
  chmod +x /etc/init.d/p0f
  update-rc.d dionaea defaults
  update-rc.d p0f defaults
  echo "Dionaea install complete! You may wish to alter the enabled handlers and services in /opt/dionaea/etc/dionaea."
fi

# Install DionaeaFR.
if [ "$INSTALL_DIONAEAFR" == "yes" ]; then
  echo "Installing DionaeaFR..."
  pip install Django==1.11 django-compressor django-filter==1.1 django-htmlmin django-pagination django-tables2==1.21.2 pygeoip six
  apt install python-netaddr -y
  cd /opt
  git clone https://github.com/phage-nz/DionaeaFR.git
  cd DionaeaFR
  mkdir tmp
  cd tmp
  git clone https://github.com/benjiec/django-tables2-simplefilter
  cd django-tables2-simplefilter
  python setup.py install
  cd ..
  git clone git://git.bro-ids.org/pysubnettree.git
  cd pysubnettree
  python setup.py install
  cd ..
  wget http://nodejs.org/dist/v4.7.1/node-v4.7.1.tar.gz  
  tar xzvf node-v4.7.1.tar.gz
  cd node-v4.7.1
  ./configure
  make
  make install
  cd ..
  wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
  wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCountry/GeoIP.dat.gz
  gunzip GeoLiteCity.dat.gz
  gunzip GeoIP.dat.gz
  mv GeoIP.dat /opt/DionaeaFR/DionaeaFR/static
  mv GeoLiteCity.dat /opt/DionaeaFR/DionaeaFR/static
  cd ..
  rm -rf tmp
  apt install npm -y
  npm install -g less -y
  echo "Fixing up DionaeaFR settings file..."
  cp /opt/DionaeaFR/DionaeaFR/settings.py.dist /opt/DionaeaFR/DionaeaFR/settings.py
  sed -i 's#/var/lib/dionaea/logsql.sqlite#/opt/dionaea/var/dionaea/dionaea.sqlite#g' /opt/DionaeaFR/DionaeaFR/settings.py
  sed -i 's/HOST.NAME/'"$HOST_NAME"'/g' /opt/DionaeaFR/DionaeaFR/settings.py
  mkdir /var/run/dionaeafr
  mkdir /var/log/dionaeafr
  echo "Preparing static content..."
  python manage.py collectstatic --noinput
  echo "Performing outstanding DB migrations..."
  python manage.py migrate --noinput
  echo "Making logrotate script..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/dionaeafr.logrotate -O /etc/logrotate.d/dionaeafr
  echo "Setting service to autostart..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/dionaeafr.init -O /etc/init.d/dionaeafr
  chmod +x /etc/init.d/dionaeafr
  update-rc.d dionaeafr defaults
  echo "DionaeaFR install complete!"
fi

# Install Cowrie.
if [ "$INSTALL_COWRIE" == "yes" ]; then
  echo "Installing Cowrie..."
  apt install libffi-dev libgmp-dev libmpc-dev libmpfr-dev libpython-dev python-virtualenv -y
  # Cowrie requires the latest version of Python OpenSSL.
  apt remove python-openssl -y
  pip install pyopenssl
  cd /opt
  git clone https://github.com/micheloosterhof/cowrie.git
  cd cowrie
  cp cowrie.cfg.dist cowrie.cfg
  mkdir tmp
  cd tmp
  # Cowrie requires the latest verison of Twisted.
  git clone -b trunk https://github.com/twisted/twisted.git
  cd twisted
  python setup.py install
  cd ../..
  rm -rf tmp
  pip install -U -r requirements.txt
  echo "Making underprivileged user..."
  useradd -r -s /bin/false cowrie
  mkdir -p /var/run/cowrie
  chown -R cowrie:cowrie /opt/cowrie/
  chown -R cowrie:cowrie /var/run/cowrie/
  mkdir /home/cowrie
  chown cowrie:cowrie /home/cowrie
  echo "Fixing up the Cowrie config file..."
  sed -i 's/^\(hostname\s*=\s*\).*/\1'"$SERVER"'/' cowrie.cfg
  echo "Making the Cowrie filesystem..."
  /opt/cowrie/bin/createfs
  echo "Making logrotate script..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/cowrie.logrotate -O /etc/logrotate.d/cowrie
  echo "Setting service to autostart..."
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/cowrie.service -O /etc/systemd/system/cowrie.service
  wget https://raw.githubusercontent.com/phage-nz/malware-hunting/master/honeypot/cowrie.socket -O /etc/systemd/system/cowrie.socket
  sed -i 's/tcp:2222:interface=0.0.0.0/systemd:domain=INET:index=0/g' /opt/cowrie/cowrie.cfg
  sed -i 's/tcp:2223:interface=0.0.0.0/systemd:domain=INET:index=1/g' /opt/cowrie/cowrie.cfg
  systemctl daemon-reload
  systemctl enable --now cowrie.socket
  systemctl enable cowrie.service
  echo "Redirecting port 22 and 23 to Cowrie. You will need to re-establish your SSH session on port 8925 after the service reloads."
  sed -i 's/Port 22/Port 8925/g' /etc/ssh/sshd_config
  service ssh reload
  iptables -t nat -A PREROUTING -p tcp --dport 22 -j REDIRECT --to-port 2222
  iptables -t nat -A PREROUTING -p tcp --dport 23 -j REDIRECT --to-port 2223
  iptables-save > /etc/iptables.rules
  echo '#!/bin/sh' >> /etc/network/if-up.d/iptablesload 
  echo 'iptables-restore < /etc/iptables.rules' >> /etc/network/if-up.d/iptablesload 
  echo 'exit 0' >> /etc/network/if-up.d/iptablesload
  chmod +x /etc/network/if-up.d/iptablesload
  echo "Cowrie install complete!"
fi

# Start services.
echo "Starting services..."

# Start Dionaea.
if [ "$INSTALL_DIONAEA" == "yes" ]; then
  /etc/init.d/p0f start
  /etc/init.d/dionaea start
fi

# Start DionaeaFR.
if [ "$INSTALL_DIONAEAFR" == "yes" ]; then
  /etc/init.d/dionaeafr start
fi

# Start Cowrie.
if [ "$INSTALL_COWRIE" == "yes" ]; then
  service cowrie start
fi

exit 0
