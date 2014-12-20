#!/usr/bin/env zsh
set -e
self_name=$0

function err
{
	[[ -n $2 ]] && echo $2 >&2
	return $1
}

function cfg_err
{
	[[ -n $1 ]] && echo "$1 is not set in configuration, but is required by $0 to work." >&2
	return 5
}

function usage
{
	echo "usage: $self_name [--help|--config]
	--help    -h - show this message
	--config  -c - use config from the specified path
	
	Default config path /usr/local/etc/backup.cfg will be used if invoked without options"
}

function read_config
{
	source $cfg || err 15 'Config file does not exist'
	[[ -z $source_dir ]] && cfg_err 'Backup source'
	[[ -z $remote_host ]] && cfg_err 'Remote host'
	[[ -z $protocol ]] && cfg_err 'Backup protocol'
	[[ -z $backup_dir && $protocol != 'ssh' ]] && cfg_err 'Target directory'
	if [[ -z $local_host ]]; then
		local_host=$HOST
	fi
	src_basename=${source_dir:t}
	src_basedir=${source_dir:h}
}

function generate_fullpath
{
	local backup_type
	local postfix
	if [[ -z $outfile_postfix ]]; then
		postfix=$default_postfix
	else
		postfix=$outfile_postfix
	fi
	if [[ -s $snap_file ]]; then
		backup_type='incr'
	else
		backup_type='full'
	fi
	if [[ -z $backup_filename ]]; then
		outfile="$backup_dir/${local_host}-${src_basename}_${postfix}_${backup_type}.t${compress_format:-'ar'}"
	else
		outfile=$backup_filename
	fi
}

function compress # compress to stdout
{
	local compress_flag
	local exclude_option
	local snapshot_option
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
	if [[ -n $snap_file ]]; then
		if printf '' >> $snap_file; then
			snapshot_option='-g'
		else
			err 1 "Snapshot file $snap_file cannot be written."
		fi
	fi
	tar cf$compress_flag - -C $src_basedir $src_basename $snapshot_option $snapshot_file $exclude_option $exclude_list --ignore-failed-read
}

function store # store to local or remote
{
	if [[ -z $remote_port ]]; then
		case $protocol in
			('ftp'|'ftps') remote_port='21';;
			('sftp'|'ssh') remote_port='22';;
			('local') unset remote_port;;
			(*) err 1 "$protocol is not a valid value for the protocol option.";;
		esac
	fi
	case $protocol in
		('local') dd of=$outfile ;;
		('ssh') ssh -p$remote_port $remote_user@$remote_host "dd of=$outfile" ;;
		('sftp'|'ftp'|'ftps') curl -ksS -T - $protocol://$remote_host:$remote_port/$outfile -u $remote_user:$remote_pass ;;
		(*) err 1 'Wrong protocol!' ;;
	esac
}

function main
{
	while [[ -n $1 ]]; do
		case $1 in
			('--help'|'-h') usage; return 0;;
			('--config'|'-c') shift; opt_cfg=$1; shift;;
		esac
	done
	cfg=${opt_cfg:-'/usr/local/etc/backup.cfg'}
	default_postfix=$(date +%F-%H%M)
	read_config
	generate_fullpath
	compress | store
	return 0
}

main $@
