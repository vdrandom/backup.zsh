#!/usr/bin/env zsh
# Default config file
default_cfg='/usr/local/etc/backup.cfg'

# Default date postfix
default_postfix=$(date +%F-%H%M)

function err
{
	[[ -n $2 ]] && echo $2 >&2
	return $1
}

function default_ports
{
	if [[ -z $port_remote ]]; then
		case $protocol in
			('ftp') remote_port='21';;
			('sftp'|'ssh') remote_port='22';;
			(*) err 1 "$protocol is not a valid value for the protocol option.";;
		esac
	fi
}

function generate_fullpath
{
	src_basename=${src_fullpath:t}
	src_basedir=${src_fullpath:h}
	if [[ -s $snap_file ]]; then
		backup_type='incr'
	else
		backup_type='full'
	fi
	if [[ -z $backup_directory && $protocol != 'ssh' ]]; then
		err 1 "You have not set the backup directory path."
	elif [[ -z $backup_filename ]]; then
		outfile="$backup_directory/$host_local\-$src_basename\_$postfix\_$backup_type.t${compress_format:-ar}"
	else
		outfile=$backup_filename
	fi
}

function compress # compress to stdout
{
	case $compress_format in
		('xz') compress_flag='J' ;;
		('bz2') compress_flag='j' ;;
		('gz') compress_flag='z' ;;
		('') unset compress_flag; unset compress_format ;;
		(*) err 1 "$compress_format is not a valid value for the compression format option.";;
	esac
	if [[ -n $exclude_list ]]; then
		if [[ -r $exclude_list ]]; then
			exclude_option='-X'
		else
			err 1 "Exclusion list $exclude_list is either unreadable or does not exist."
		fi
	fi
	if [[ -n $snap_file && -n $incremental_backup ]]; then
		if printf '' >> $snap_file; then
			snapshot_option='-g'
		else
			err 1 "Snapshot file $snap_file cannot be written."
		fi
	fi
	tar cf$compress_flag - -C $src_basedir $src_basename $snapshot_option $snapshot_file $exclude_option $exclude_list --ignore-failed-read
}

function encrypt # encrypt if encryption is needed
{
	if [[ -n $gnupg_key ]]; then
		gpg -r $gnupg_key -e -
	else
		read _
		print $_
	fi
}

function store # store to local or remote
{
	case $protocol in
		('local') dd of=$outfile ;;
		('ssh') ssh -p$port_remote $user_remote@$host_remote "dd of=$outfile" ;;
		('sftp'|'ftp'|'ftps') curl -ksS -T - $protocol://$host_remote:$port_remote/$outfile -u $user_remote:$pass_remote ;;
		(*) err 1 'Wrong protocol!' ;;
	esac
}
