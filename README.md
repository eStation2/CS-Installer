# Climate Station - Python 3.8.10 in Docker 
## Introduction

This installation contains the Climate Station code (from the master branch) converted to Python 3.7 or higher
For the database PostgreSQL 12 is used, for which the code had to be adapted to the latest version of SQLAlchemy.

## Software requirements
The Climate Station (CS) installer needs the following software packages to be installed on the host machine: 

•	Docker engine (version 19.03+)

•	Docker compose (version 1.29+)

•	Git (version 2.22+)


# PREPARATION OF THE INSTALLATION
## User Definition
The user on the host machine that installs the software requirements must have privileges for this. This can be done in two ways:

● Have your system administrator install these requirements as root.

● Give sudo(super user do) rights to install the requirements to the CS user created on the host machine (by your system administrator, see below) .

On the host machine, it is considered best practice to not use the “root” user for installing an application, but to create a CS user with “sudo” rights.

Create a user (e.g. adminuser) and give this user sudo rights:

```bash
$ adduser adminuser sudo
$ usermod -aG sudo adminuser
```

## Installation of Docker and Docker Compose
Install all packages as root or as a user with sudo rights. All following commands are done by the CS user with sudo.

Docker Engine
Please follow the installation instructions for the OS on your host machine: 
https://docs.docker.com/engine/install/  

Docker-compose
Installation instructions: 
https://docs.docker.com/compose/install/  
https://pypi.org/project/docker-compose/ 

●  Install the required packages and dependencies:

```bash
	$ sudo yum install python3-pip
	$ sudo yum install rust
	$ sudo pip3 install –upgrade pip
	$ sudo pip3 install setuptools
	$ sudo pip3 install setuptools-rust
```
●  Install docker-compose:	

```bash
	$ sudo pip3 install docker-compose
```
Once the installation is completed, check if it is installed fine by checking its version in the command prompt as follows:

●	Docker engine → docker --version
```bash
		$ docker --version
        Docker version 20.10.14, build a224086
```

●	Docker Compose → docker-compose --version
```bash
		$ docker-compose --version
        docker-compose version 1.28.5, build unknown
```
 
## Installation of GIT
The Climate Station installation package is made available in the git, so in order to install it you have to install git  in your machine either as root user or as a user (eg. adminuser) with sudo rights. For example if you’re on a Debian-based distribution, such as Ubuntu, try apt:
```bash
$ sudo apt install git
```

Once installation is completed, check if it is installed fine by checking its version in command prompt as below:
```bash
$ git --version
git version 1.8.3.1

```

## Cloning the ClimateStation code from Github
To download the code of the Climate Station you will have to clone the climatestation repository from github on your local machine.

After you installed Git on your computer, open a Terminal and run the following commands:

•	First move to the directory where you want to create the clone. This will be the root directory of the installation indicated as <climatestation_dir>:

```bash
$ cd  <climatestation_dir> (eg. /opt or /home/adminuser)
```

•	Execute git-clone:

```bash
$ git clone https://github.com/eStation2/CS-Installer.git 
Cloning into "CS-Installer" ...
remote: Enumerating objects: 17901, done.
remote: Counting objects: 100% (17901/17901), done.
remote: Total 25110 (delta 3689), reused 17689 (delta 3527), pack-reused 7209
Receiving objects: 100% (25110/25110), 173.65MiB | 11.68 MiB/s, done.
Resolving deltas: 100% (6625/6625), done.
Checking out files: 100% (34362/34362), done.
```

•	Check the content of the directory where the clone has been created and it should contain the following files and directories:

```bash
$ cd CS-Installer
$  ls -sla
0	drwxrwxr-x 	8 	adminuser adminuser 	321 	May 	4	11:39	.
4	drwx------	14 	adminuser adminuser 	4096	May 	5 	16:07 	..
20	-rwxrwxr-x 	1 	adminuser adminuser	20341	May 	4 	1:39 	cs_install.sh
4	-rw-rw-r-- 	1 	adminuser adminuser 	3466 	May 	4 	11:39 	docker-compose.yml
4	-rw-rw-r-- 	1 	adminuser adminuser 	897 	May 	4 	10:02 	.env.template
 
```


# INSTALLATION OF THE CLIMATE STATION

## Checking the Current Installation And Settings
Running the command below for the first time, will check the current installation version and settings.

Make sure that the internet connection is stable!

Open a Terminal and run the following commands:

```bash
$ cd  <CS-Installer_dir> (e.g. /opt/climatestation)

$ ./cs_install.sh -p      [do not run it as root (sudo)]
```
You will be asked to change the settings in the .env file (see figure below).


![image](https://user-images.githubusercontent.com/9166401/169016554-7821a4cb-4f7e-42b0-820d-33e7332d7cbc.png)

## Customize User Settings
For the installation of the Climate Station, there are some important definitions that might need to be updated before continuing the installation, e.g the working directories on the host machine, the proxy settings and others. All these variables are defined in the .env file, which is in the root directory of the installation after you have run ./climatestation.sh the first time (see Figure above).
You can use ‘vi’ (or another editor like nano or gedit) - to modify definitions in the .env file.

```bash
$ cd <climatestation_dir> (e.g. /opt/climatestation) 
$ vi .env
```
![image](https://user-images.githubusercontent.com/9166401/169018064-452a0bda-f029-449d-8427-1df0bcb51464.png)

A number of parameters (Figure above) can be customized to match the User’s environment, in terms of volume mapping, proxy definition.

### Optional:

•	DATA_VOLUME is the base directory for the installation of the data, both static data and datasets (default /data).

•	TMP_VOLUME is a working directory for temporary files, e.g. intermediate steps of computation (default /tmp/climatestation).

●	The 4 PROXY definitions (HTTP_PROXY, HTTPS_PROXY, FTP_PROXY, NO_PROXY) have to be used in case the host machine operates behind a proxy, and are needed to reach the internet.

●	CS_PGPORT by default is 5431 in our installation, but if that port is already used by another service, you can modify it.

●	CS_WEBPORT by default is 8080 in our installation, but if that port is already used by another service, you can modify it.


### Mandatory:
•	To have the Jupyter Notebook to work, you should edit the variable “SRC_DIR” with the working directory followed by “src”. The working directory is the directory where you cloned the Climate Station, eg. SRC_DIR=/opt/climatestation/src


## Building and Starting the Climate Station
Now that the user settings have been corrected (if needed), we can build and start the Climate Station. Make sure that the internet connection is stable.

Open a Terminal and run the following commands:

```bash
$ cd <CS-Installer-dir>  (e.g. /opt/climatestation)
$ ./cs_install.sh -p     [do not run it as root (sudo)]
```

The first time you build the Climate Station might take up to 20 minutes.
Output when build has finished:
 

# POST INSTALLATION OPERATIONS AND CHECKS
## Check If the Climate Station is Running Well

How to check if the Climate Station is running well?

Open a web browser and go to:

http://localhost:8080 
![image](https://user-images.githubusercontent.com/9166401/169018827-bf2d0109-6d67-4925-8464-6563ecfda063.png)

 
## Checking the Data and Other Directories

Check the existence of the following directories under the DATA directory indicated in the .env file, by default the /data directory on your host machine.

On the first build and start of the Climate Station, using ./climatestation.sh (see section 3.3), the sub directories under the /data directory will be created as follows:
 
The "data" directory will contain the directories:
+ processing
+ ingest
+ ingest.wrong
+ static_data

The "static_data" sub directory will contain the following directories:
+ completeness_bars
+ db_dump
+ docs   
+ get_lists
 + layers
 + log
 + logos
 + requests
 + settings

## Download of Static Data [Temp]
The Climate Station uses vector layers (border, marine and other layers) that have to be downloaded and copied under the static_data folder in their respective subdirectories.

You can download the static data (layers and logos) from the JRC SFTP server:

    - host: srv-ies-ftp.jrc.it
    - username: narmauser
    - pwd: JRCkOq7478
    - directory: /narma/eStation_2.0/static_data
    
sftp://narmauser:JRCkOq7478@srv-ies-ftp.jrc.it/narma/eStation_2.0/static_data

Unzip the corresponding files in their respective directory under the static_data directory, see section above.


## Controlling the Climate Station Application

Run the following commands under the Climate Station directory:

```bash
$ cd  <CS-Installer_dir>  (e.g. /opt/climatestation)
```

Stopping the Climate Station
```bash
$ ./cs_install.sh down
```

Starting the Climate Station
```bash
$ ./cs_install.sh up
```

Restarting the Climate Station
```bash
$ ./cs_install.sh down
$ ./cs_install.sh up
```
 
# UPGRADING THE CLIMATE STATION

First go into the directory where the Climate Station has been cloned, shutdown CS and then pull the upgrade from git and start CS. 

OPEN A TERMINAL AND TYPE IN THE FOLLOWING COMMANDS: 
```bash
$ cd <CS-Installer_dir>   (e.g. /opt/climatestation)
```
●	Stop the Climate Station

```bash
$ ./cs_install.sh down
```

●	Update the Climate Station

```bash
$ git pull
$ ./cs_install.sh -p
```
