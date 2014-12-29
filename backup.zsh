#!/usr/bin/env zsh
self_name=$0
default_cfg='/usr/local/etc/backup.cfg'
default_postfix=$(date +%F-%H%M)
default_ftp_port='21'
default_ssh_port='22'

function err
{
	[[ -n $1 ]] && echo $1 >&2
}

function cfg_err
{
	[[ -n $1 ]] && echo "$1 is not set in configuration, but is required by $0 to work." >&2
}

function usage
{
	echo "usage: $self_name [--help|--config]
	--help    -h - show this message
	--config  -c - use config from the specified path

	Default config path /usr/local/etc/backup.cfg will be used if invoked without options"
}

# function to read the configuration file and spit out some exceptions if stuff is missing
function apply_config
{
	source $cfg || err 15 'Config file does not exist'
	if [[ -z $source_dirs ]]; then
		cfg_err 'Backup source'
		exit 5
	fi
	if [[ -z $remote_host ]]; then
		cfg_err 'Remote host'
		exit 5
	fi
	if [[ -z $backup_dir && $protocol != 'ssh' ]]; then
		cfg_err 'Target directory'
		exit 5
	fi
	if [[ -z $local_host ]]; then
		local_host=$HOST
	fi
	# date postfix
	if [[ -z $outfile_postfix ]]; then
		postfix=$default_postfix
	else
		postfix=$outfile_postfix
	fi
	case $protocol in
		('ftp'|'ftps') port=${remote_port:-$default_ftp_port};;
		('sftp'|'ssh') port=${remote_port:-$default_ssh_port};;
		('local') unset remote_port;;
		(*) cfg_err 'Backup protocol'; exit 5;;
	esac
	if [[ ! $remote_port =~ ^[0-9]+$ ]]; then
		err 'Remote port is not a numeric value.'
	fi
	case $compress_format in
		('xz') compress_flag='J' ;;
		('bz2') compress_flag='j' ;;
		('gz') compress_flag='z' ;;
		('') unset compress_flag; unset compress_format ;;
		(*) err "$compress_format is not a valid value for the compression format option."; exit 5;;
	esac
	if [[ -n $exclude_list ]]; then
		if [[ -r $exclude_list ]]; then
			exclude_option='-X'
		else
			err "Exclusion list $exclude_list is either unreadable or does not exist."
		fi
	fi
	if [[ -n $snap_file ]]; then
		if printf '' >> $snap_file; then
			snapshot_option='-g'
		else
			err "Snapshot file $snap_file cannot be written."
		fi
	fi
}

# generate the full backup path
function generate_fullpath
{
	local backup_type
	# increment or full backup
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
	tar cf$compress_flag - -C $src_basedir $src_basename $snapshot_option $snapshot_file $exclude_option $exclude_list --ignore-failed-read
}

function store # store to local or remote
{
	case $protocol in
		('local') dd of=$outfile ;;
		('ssh') ssh -p$port $remote_user@$remote_host "dd of=$outfile" ;;
		('sftp'|'ftp'|'ftps') curl -ksS -T - $protocol://$remote_host:$port/$outfile -u $remote_user:$remote_pass ;;
	esac
}

function parse_opts
{
	while [[ -n $1 ]]; do
		case $1 in
			('--help'|'-h') usage; return 0;;
			('--config'|'-c') shift; opt_cfg=$1; shift;;
		esac
	done
}

function main
{
	parse_opts
	if [[ -z $opt_cfg ]]; then
		cfg=$default_cfg
	else
		cfg=$opt_cfg
	fi
	apply_config
	for i in $source_dirs; do
		unset src_basename src_basedir outfile
		IFS=':' read source_dir snap_file <<< $i
		src_basename=${source_dir:t}
		src_basedir=${source_dir:h}
		generate_fullpath
		compress | store
	done
	return 0
}

main $@
