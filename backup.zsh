#!/usr/bin/env zsh
self_name=$0
default_cfg='/etc/backup.zsh.cfg'
default_postfix=$(date +%F-%H%M)
default_ftp_port='21'
default_ssh_port='22'

# echo to stderr
function err
{
	[[ -n $1 ]] && echo $1 >&2
}

# standard configuration error message to stderr
function cfg_err
{
	[[ -n $1 ]] && echo "$1 is not set in configuration, but is required by $self_name to work." >&2
}

# print help
function usage
{
	echo "usage: $self_name [--help|--conf /path/to/config]
	--help  -h   show this message
	--conf  -c   use config from the specified path

	Default config path $default_cfg will be used if invoked without options"
}

# read the configuration file and spit out some exceptions if stuff is missing
function apply_config
{
	# testing remote settings only needed for non-local backups
	function test_remote_settings
	{
		if [[ -z $remote_host ]]; then
			cfg_err 'remote_host'
			return 5
		fi
		if [[ -z $remote_user ]]; then
			cfg_err 'remote_user'
			return 5
		fi
		if [[ -z $remote_pass ]]; then
			cfg_err 'remote_pass'
			return 5
		fi
		if [[ -n $port && ! $port =~ ^[0-9]+$ ]]; then
			err 'Remote port is not a numeric value.'
			return 5
		fi
	}
	# import contents of the config (including functions if present)
	source $cfg || { err "Config file $cfg is unreadable or does not exist"; return 15 }
	# do the tests
	if [[ -z $source_dirs ]]; then
		cfg_err 'source_dirs'
		return 5
	fi
	if [[ -z $backup_dir && $protocol != 'ssh' ]]; then
		cfg_err 'backup_dir'
		return 5
	fi
	if [[ -z $local_host ]]; then
		err 'local_host is not set, using hostname.'
		local_host=$HOST
	fi
	if [[ -z $outfile_postfix ]]; then
		postfix=$default_postfix
	else
		postfix=$outfile_postfix
	fi
	# set defaults and / or fail to run if something is missing
	case $protocol in
		('ftp'|'ftps') port=${remote_port:-$default_ftp_port}; test_remote_settings; return $?;;
		('sftp'|'ssh') port=${remote_port:-$default_ssh_port}; test_remote_settings; return $?;;
		('local') unset remote_port;;
		(*) cfg_err 'protocol'; return 5;;
	esac
	# set variables for tar command
	case $compress_format in
		('xz') compress_flag='J' ;;
		('bz2') compress_flag='j' ;;
		('gz') compress_flag='z' ;;
		('') unset compress_flag; unset compress_format ;;
		(*) err "$compress_format is not a valid value for the compression format option."; return 5;;
	esac
	if [[ -n $exclude_list ]]; then
		if [[ -r $exclude_list ]]; then
			exclude_option='-X'
		else
			err "Exclusion list $exclude_list is either unreadable or does not exist. Proceeding without it."
		fi
	fi
}

# generate the full backup path
function generate_fullpath
{
	local backup_type
	# increment or full backup
	if [[ -s $snapshot_file ]]; then
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

# compress to stdout
function compress
{
	# snapshot file is per directory so we cannot test it within apply_config()
	if [[ -n $snapshot_file ]]; then
		if printf '' >> $snapshot_file; then
			snapshot_option='-g'
		else
			err "Snapshot file $snapshot_file cannot be written. Proceeding with full backup."
		fi
	fi
	# do the magic and spit to stdout
	tar -c$compress_flag $snapshot_option $snapshot_file $exclude_option $exclude_list --ignore-failed-read -C $src_basedir $src_basename
}

# store to local or remote
function store
{
	# take from stdin and do the magic
	case $protocol in
		('local') dd of=$outfile ;;
		('ssh') ssh -p$port $remote_user@$remote_host "dd of=$outfile" ;;
		('sftp'|'ftp'|'ftps') curl -ksS -T - $protocol://$remote_host:$port/$outfile -u $remote_user:$remote_pass ;;
	esac
}

# self explanatory, using case statement, so no one dash multiple opts supported
function parse_opts
{
	while [[ -n $1 ]]; do
		case $1 in
			('--help'|'-h') usage; exit 0;;
			('--conf'|'-c') shift; opt_cfg=$1; shift;;
			(*) err "unknown parameter $1"; exit 127;;
		esac
	done
}

# the main logic
function main
{
	# parse options
	parse_opts $@
	# set default config if $opt_cfg is not defined via an option
	cfg=${opt_cfg:-$default_cfg}
	# run config tests and fill in defaults
	apply_config
	# fail in case something goes wrong
	local apply_config_returns=$?
	[[ $apply_config_returns -ne 0 ]] && return $apply_config_returns
	# run backups per directory
	for i in $source_dirs; do
		# prepare the set of variables
		unset src_basename src_basedir outfile
		IFS=':' read source_dir snapshot_file <<< $i
		src_basename=${source_dir:t}
		src_basedir=${source_dir:h}
		# generate the backups path
		generate_fullpath
		err "Creating a backup of $source_dir via $protocol to store it in $outfile."
		# pipe magic into magic
		compress | store
	done
	return 0
}

main $@
