{ sudo ? (import <nixpkgs> { }).sudo }:
/*
  This description is yanked from this commit:
  https://github.com/ma27/nixpkgs/commit/e12408af98b8903d295539a68d9d4fe9fd0a18fe

  This is a slightly modified sudo enabling `--enable-static-sudoers`
  which ensures that `sudoers.so` is linked statically into the
  executable[1]:

  >  --enable-static-sudoers
  >        By default, the sudoers plugin is built and installed as a
  >        dynamic shared object.  When the --enable-static-sudoers
  >        option is specified, the sudoers plugin is compiled directly
  >        into the sudo binary.  Unlike --disable-shared, this does
  >        not prevent other plugins from being used and the intercept
  >        and noexec options will continue to function.

  This is necessary here because of user-namespaced `nspawn`-instances:
  these have their own UID/GID-range. If a container called `ldap` has
  `PrivateUsers=pick` enabled, this may look like this:

  $ ls /var/lib/machines
  drwxr-xr-x 15 vu-ldap-0  vg-ldap-0  15 Mar 11  2021 ldap
  -rw-------  1 root       root        0 Sep 12 16:13 .#ldap.lck
  $ id vu-ldap-0
  uid=1758003200(vu-ldap-0) gid=65534(nogroup) groups=65534(nogroup)

  However, this means that bind-mounts (such as `/nix/store`) will be
  owned by `nobody:nogroup` which is a problem for `sudo(8)` which expects
  `sudoers.so` being owned by `root`.

  To work around this, the aforementioned configure-flag will be used to
  ensure that this library is statically linked into `bin/sudo` itself. We
  cannot do a full static build though since `sudo(8)` still needs to
  `dlopen(3)` various other libraries to function properly with PAM.
*/
sudo.overrideAttrs (final: prev: {
  configureFlags = prev.configureFlags ++ [ "--enable-static-sudoers" ];
})
