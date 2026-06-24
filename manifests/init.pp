# @summary Creates and maintains a yum repository.
#
# Manages a repository root directory, installs the `createrepo` (or
# `createrepo_c`) package, renders a metadata-update script and optionally
# schedules updates via cron and/or runs them during the Puppet agent run.
#
# This define does not manage the directory tree above `$repository_dir`
# and does not manage an HTTP server.
#
# @param repository_dir
#   The path to the base directory of the repository. Here, or in
#   subdirectories, you store the .rpm files.
# @param repo_cache_dir
#   Path to a checksum directory. Makes updates to the repository faster.
# @param repo_owner
#   Owner of the repository directory.
# @param repo_group
#   Group of the repository directory.
# @param repo_mode
#   Mode of the repository directory.
# @param repo_recurse
#   Enable recursive management of the repository directory.
# @param repo_ignore
#   Ignore-list for recursive management of the repository directory.
# @param repo_seltype
#   SELinux type for the repository directory.
# @param enable_cron
#   Enable automatic repository updates via cron.
# @param enable_update
#   Enable automatic repository updates during the Puppet run.
# @param cron_minute
#   Minute parameter for cron metadata update job.
# @param cron_hour
#   Hour parameter for cron metadata update job.
# @param cron_weekday
#   Weekday parameter for cron metadata update job.
# @param changelog_limit
#   Import only last N changelog entries from rpm into metadata.
#   (RedHat-family only.)
# @param checksum_type
#   For compatibility with older versions of yum. (RedHat-family only.)
# @param update_file_path
#   Location of repo update script. If `undef`, defaults to
#   `/usr/local/bin/createrepo-update-<sanitized-name>`.
# @param suppress_cron_stdout
#   Redirect stdout output from cron to /dev/null.
# @param suppress_cron_stderr
#   Redirect stderr output from cron to /dev/null.
# @param groupfile
#   Provide a groupfile, e.g. comps.xml.
# @param workers
#   Number of workers to spawn to read RPMs.
# @param timeout
#   Exec timeout for createrepo commands, in seconds.
# @param manage_repo_dirs
#   Manage the repository and cache directories. When `false`, both
#   directories must be created out-of-band.
# @param cleanup
#   When `true`, the update script removes old rpm versions for each rpm.
# @param cleanup_keep
#   How many versions of each rpm to keep when `cleanup` is `true`.
# @param use_lockfile
#   Prevent corruption of the repodata when multiple createrepo
#   processes start building metadata at the same time.
# @param lockfile
#   Full path of the lockfile used when `use_lockfile` is `true`.
# @param createrepo_package
#   Package providing the createrepo binary. Set to `createrepo_c` to use
#   the C implementation.
# @param createrepo_cmd
#   Path of the createrepo binary to invoke. Must be kept in sync with
#   `$createrepo_package` by the caller.
#
# @example Basic usage
#   createrepo { 'yumrepo':
#     repository_dir => '/var/yumrepos/yumrepo',
#     repo_cache_dir => '/var/cache/yumrepos/yumrepo',
#   }
#
define createrepo (
  Stdlib::Absolutepath           $repository_dir       = "/var/yumrepos/${name}",
  Stdlib::Absolutepath           $repo_cache_dir       = "/var/cache/yumrepos/${name}",
  String[1]                      $repo_owner           = 'root',
  String[1]                      $repo_group           = 'root',
  Stdlib::Filemode               $repo_mode            = '0775',
  Boolean                        $repo_recurse         = false,
  Optional[Array[String[1]]]     $repo_ignore          = undef,
  String[1]                      $repo_seltype         = 'httpd_sys_content_t',
  Boolean                        $enable_cron          = true,
  Boolean                        $enable_update        = false,
  String[1]                      $cron_minute          = '*/10',
  String[1]                      $cron_hour            = '*',
  String[1]                      $cron_weekday         = '*',
  Integer[0]                     $changelog_limit      = 5,
  Optional[String[1]]            $checksum_type        = undef,
  Optional[Stdlib::Absolutepath] $update_file_path     = undef,
  Boolean                        $suppress_cron_stdout = false,
  Boolean                        $suppress_cron_stderr = false,
  Optional[String[1]]            $groupfile            = undef,
  Optional[Integer[1]]           $workers              = undef,
  Integer[0]                     $timeout              = 300,
  Boolean                        $manage_repo_dirs     = true,
  Boolean                        $cleanup              = false,
  Integer[0]                     $cleanup_keep         = 2,
  Boolean                        $use_lockfile         = false,
  Stdlib::Absolutepath           $lockfile             = "/tmp/createrepo-update-${name}.lock",
  String[1]                      $createrepo_package   = 'createrepo',
  Stdlib::Absolutepath           $createrepo_cmd       = '/usr/bin/createrepo',
) {
  $real_update_file_path = $update_file_path ? {
    undef   => "/usr/local/bin/createrepo-update-${regsubst($name, '/', '-', 'G')}",
    default => $update_file_path,
  }

  if $manage_repo_dirs {
    file { $repository_dir:
      ensure  => directory,
      owner   => $repo_owner,
      group   => $repo_group,
      mode    => $repo_mode,
      recurse => $repo_recurse,
      ignore  => $repo_ignore,
      seltype => $repo_seltype,
      before  => Exec["createrepo-${name}"],
    }
    file { $repo_cache_dir:
      ensure => directory,
      owner  => $repo_owner,
      group  => $repo_group,
      mode   => $repo_mode,
      before => Exec["createrepo-${name}"],
    }
  }

  ensure_packages([$createrepo_package])

  if $cleanup {
    ensure_packages(['yum-utils'])
    Package['yum-utils'] -> File[$real_update_file_path]
  }

  case $facts['os']['family'] {
    'RedHat': {
      $_arg_changelog = " --changelog-limit ${changelog_limit}"
      $_arg_checksum  = $checksum_type ? {
        undef   => '',
        default => " --checksum ${checksum_type}",
      }
    }
    default: {
      # createrepo distributed with some OS doesn't have these options
      $_arg_changelog = ''
      $_arg_checksum  = ''
    }
  }

  $_stdout_suppress = $suppress_cron_stdout ? { true => ' 1>/dev/null', default => '' }
  $_stderr_suppress = $suppress_cron_stderr ? { true => ' 2>/dev/null', default => '' }

  $_arg_groupfile = $groupfile ? {
    undef   => '',
    default => " --groupfile ${groupfile}",
  }
  $_arg_workers = $workers ? {
    undef   => '',
    default => " --workers ${workers}",
  }

  $_arg_cachedir          = "--cachedir ${repo_cache_dir}"
  $arg                    = "${_arg_cachedir}${_arg_changelog}${_arg_checksum}${_arg_groupfile}${_arg_workers}"
  $cron_output_suppression = "${_stdout_suppress}${_stderr_suppress}"
  $createrepo_create      = "${createrepo_cmd} ${arg} --database ${repository_dir}"
  $createrepo_update      = "${createrepo_cmd} ${arg} --update ${repository_dir}"
  $repomanage_cleanup     = "/usr/bin/repomanage --keep=${cleanup_keep} --old ${repository_dir} | /usr/bin/xargs -r rm"

  exec { "createrepo-${name}":
    command => $createrepo_create,
    user    => $repo_owner,
    group   => $repo_group,
    creates => "${repository_dir}/repodata",
    timeout => $timeout,
    require => Package[$createrepo_package],
  }

  file { $real_update_file_path:
    ensure  => 'file',
    owner   => $repo_owner,
    group   => $repo_group,
    mode    => '0755',
    content => template('createrepo/createrepo-update.sh.erb'),
  }

  if $enable_cron {
    cron { "update-createrepo-${name}":
      command => "${real_update_file_path}${cron_output_suppression}",
      user    => $repo_owner,
      minute  => $cron_minute,
      hour    => $cron_hour,
      weekday => $cron_weekday,
      require => [Exec["createrepo-${name}"], File[$real_update_file_path]],
    }
  }

  if $enable_update {
    exec { "update-createrepo-${name}":
      command => $real_update_file_path,
      user    => $repo_owner,
      group   => $repo_group,
      timeout => $timeout,
      require => [Exec["createrepo-${name}"], File[$real_update_file_path]],
    }
  }
}
