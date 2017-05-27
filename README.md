# Encrypted backup
Bash script to collect specified files/directories on a file system, encrypt them and backup them to Google Drive.

The script uses *veracrypt* for encrypted storage containers and *grive* as the client for Google Drive synchronization.
These two programs have to be pre-installed:

    - Veracrypt -> http://linuxg.net/how-to-install-veracrypt-1-0e-on-the-most-popular-linux-systems/
    - grive -> https://github.com/vitalif/grive2



## Usage
The script can be executed with

`bash sync_script.sh`

In the script itself, the following parameters are mandatory and have to be hardcoded:

`ENCRYPTION_CONTAINERS`: Array with location of encryption containers and a mapping number for which
files should be stored in this container, e.g.

    ENCRYPTION_CONTAINERS=(1 /path/to/container1 \
						   2 /path/to/contaienr2)


All other parameters can be defined either hardcoded in the script as well, or being passed as command line parameters:

`GRIVE_DIR`: Location of the GRIVE synchronization directory which has to be setup first (see `grive -a`)

`LOGFILE`: Location where the logfile should be created

`TIME_LAST_EXEC`: Required elapsed time between two backups (in case the synchronization should run as an automated service)

`BACKUP_FILES`: Files/Directories to be backup up. The variable has to be an array, where each file/directory is marked with a mapping number for the previously defined encryption container, e.g.

    BACKUP_FILES=(2 $HOME/Documents \         # will be stored in container 2
	      		  2 $HOME/Java \              # will be stored in container 2
                  1 $HOME/.PyCharmCE2017.1)   # will be stored in container 1



Parameters that can be passed to the script:

    Usage: sync_script.sh [-h] [-v] [-i] [-p | -b] [-f files] [-t time] [-l logfile] [-g grive_dir]
    	-h Displays help
    	-f Specify backup files
    	-t Seconds that need to be passed since last update; if 0 always backup
    	-l Specify logfile (default '/home/cerberus/Scripts/Sync/Logs/Log_sync.log')
    	-i Run also when no internet connection available (Only synchronize files)
    	-b Only upload backup files, WITHOUT synchronizing them first!
    	-p Only backup files
    	-g Specify the directory in which grive has been setup
    	-v Display log output (otherwise only logged to file)
