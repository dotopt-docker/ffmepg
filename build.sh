#!/bin/bash
# @Author: wuxingzhong
# @Date:   2018-12-03 09:52:39

# pwd
base_dir=$(pwd)
# build_dir
build_dir=${base_dir}/build
lib_dir=${build_dir}/libdeps
lib_info_dir=${lib_dir}/info_dir
prefix_dir=${build_dir}
fast_make='-j8'
cpu_count=8
clean_up=false

build_force_clean=" -B "
make_flag="${build_force_clean}"

if [ ! -d ${lib_dir} ]; then
	mkdir -p ${lib_dir}
fi

if [ ! -d ${lib_info_dir} ]; then
	mkdir -p ${lib_info_dir}
fi

# linux shell log color support.
echo_log()
{
	echo -e "\033[32;32m$*\033[0m"
}
echo_error()
{
	echo -e "\033[31;31m$*\033[0m"
}
echo_warn()
{
	echo -e "\033[33;33m$*\033[0m"
}

parse_arguments(){
	while [ "$1" != "" ]; do
		case $1 in
			"--cleanup")
				clean_up=true
				;;
			"--fast")
				fast_make='-j8'
				;;
		esac
		shift
	done
}

check_need_tools () {

	local check_packages=('curl' 'git' 'hg' \
						  'pkg-config' 'yasm' 'makeinfo' 'nasm'  'patch' \
						  'gcc' 'g++'  'make' 'cmake'  'autogen' 'autoconf' 'automake'
						  )

	for package in "${check_packages[@]}"; do
		type -P "$package" >/dev/null || missing_packages=("$package" "${missing_packages[@]}")
	done

	if [[ -n "${missing_packages[@]}" ]]; then

		echo_log "missing tools list: "
		echo_error "    ${missing_packages[@]}"
		echo_log "please install them first!!"
		exit 1
	fi
}
# do_svn_checkout ${repo_url} ${to_dir} ${desired_revision}
do_svn_checkout() {
	repo_url="$1"
	to_dir="$2"
	desired_revision="$3"
	if [ ! -d $to_dir ]; then
		echo_log "svn checking out to $to_dir"
		if [[ -z "$desired_revision" ]]; then
			svn checkout $repo_url $to_dir.tmp  --non-interactive --trust-server-cert || exit 1
		else
			svn checkout -r $desired_revision $repo_url $to_dir.tmp || exit 1
		fi
		mv $to_dir.tmp $to_dir
	else
		cd $to_dir
		echo_log "not svn Updating $to_dir since usually svn repo's aren't updated frequently enough..."
		cd ..
	fi
}

# do_git_checkout ${repo_url} ${to_dir} ${desired_branch} ${git_get_latest}
do_git_checkout() { 
	local repo_url="$1"
	local to_dir="$2"
	if [[ -z $to_dir ]]; then
		to_dir=$(basename $repo_url .git)
	fi
	local desired_branch="$3"
	local git_get_latest="$4"
	if [ ! -d $to_dir ]; then
		echo_log "Downloading (via git clone) $to_dir from $repo_url"
		rm -rf $to_dir.tmp # just in case it was interrupted previously...
		git clone $repo_url $to_dir.tmp || exit 1
		# prevent partial checkouts by renaming it only after success
		mv $to_dir.tmp $to_dir
		echo_log "done git cloning to $to_dir"
		cd $to_dir
	else
		cd $to_dir
		if [[ $git_get_latest = "y" ]]; then
			git fetch # need this no matter what
		else
			echo_log "not doing git get latest pull for latest code $to_dir"
		fi
	fi

	old_git_version=`git rev-parse HEAD`

	if [[ -z $desired_branch ]]; then
		echo_log "doing git checkout master"
		git checkout -f master || exit 1 # in case they were on some other branch before [ex: going between ffmpeg release tags]. # -f: checkout even if the working tree differs from HEAD.
		if [[ $git_get_latest = "y" ]]; then
			echo_log "Updating to latest $to_dir git version [origin/master]..."
			git merge origin/master || exit 1
		fi
	else
		echo_log "doing git checkout $desired_branch"
		git checkout "$desired_branch" || exit 1
		git merge "$desired_branch" || exit 1 # get incoming changes to a branch
	fi

	new_git_version=`git rev-parse HEAD`
	if [[ "$old_git_version" != "$new_git_version" ]]; then
		echo_log "got upstream changes, forcing re-configure."
		git clean -f # Throw away local changes; 'already_*' and bak-files for instance.
	else
		echo_log "got no code changes, not forcing reconfigure for that..."
	fi

	cd ..
}

download_and_unpack_file() {
	url="$1"
	output_name=$(basename $url)
	output_dir="$2"
	if [[ -z $output_dir ]]; then
		output_dir=$(basename $url | sed s/\.tar\.*//) # remove .tar.xx
	fi
	if [ ! -d "$output_dir" ]; then
		if [[ ! -f $output_name ]]; then
			echo_log "downloading $url"
			curl -4 "$url" --retry 50 -O -L --fail || echo_and_exit "unable to download $url"
		fi

		#  From man curl
		#  -4, --ipv4
		#  If curl is capable of resolving an address to multiple IP versions (which it is if it is  IPv6-capable),
		#  this option tells curl to resolve names to IPv4 addresses only.
		#  avoid a "network unreachable" error in certain [broken Ubuntu] configurations a user ran into once
		#  -L means "allow redirection" or some odd :|
		tar -xf "$output_name" || unzip "$output_name" || exit 1
		mv  $(basename $url | sed s/\.tar\.*//) ${output_dir}
	fi
}


do_configure() { # do_configure  configure_options configure_name
	local configure_options="$1"
	local configure_name="$2"

	if [[ "$configure_name" = "" ]]; then
		configure_name="./configure"
	fi

	local cur_dir2=$(pwd)
	if [ -f bootstrap ]; then
		./bootstrap || exit 1
	fi
	if [[ ! -f $configure_name && -f bootstrap.sh ]]; then
		./bootstrap.sh || exit 1
	fi
	if [[ ! -f $configure_name ]]; then
		autoreconf -fiv || exit 1
	fi
	local tmp_cmd="${configure_name} ${configure_options}"
	echo_log  $tmp_cmd
	eval $tmp_cmd  || exit 1 # not nice on purpose, so that if some other script is running as nice, this one will get priority :)
	nice make clean -j $cpu_count # sometimes useful when files change, etc.

	echo_log "already configured $(basename $cur_dir2)"
}



do_make() { #do_make make_option
	local extra_make_options="$1 -j $cpu_count"

	echo_log
	echo_log "making $(pwd) as $ make $extra_make_options"
	echo_log
	if [ ! -f configure ]; then
		nice make clean -j $cpu_count # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
	fi
	nice make $extra_make_options || exit 1

}

do_make_install() {
	local extra_make_install_options="$1"
	local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
	if [[ -z $override_make_install_options ]]; then
		local make_install_options="install $extra_make_install_options"
	else
		local make_install_options="$override_make_install_options $extra_make_install_options"
	fi

	echo_log "make installing $(pwd) as $ make $make_install_options"
	nice make $make_install_options || exit 1

}

do_make_and_make_install() {
	local extra_make_options="$1"
	do_make "$extra_make_options"
	do_make_install "$extra_make_options"
}


do_cmake() {
	extra_args="$1"
	local cur_dir2=$(pwd)
	echo_log doing cmake in $cur_dir2  with extra_args=$extra_args like this:
	echo_log cmake –G"Unix Makefiles"  $extra_args
	cmake –G"Unix Makefiles"   $extra_args || exit 1
}


apply_patch() {
	local url=$1 # if you want it to use a local file instead of a url one [i.e. local file with local modifications] specify it like file://localhost/full/path/to/filename.patch
	local patch_type=$2
	if [[ -z $patch_type ]]; then
		patch_type="-p0" # some are -p1 unfortunately, git's default
	fi
	local patch_name=$(basename $url)
	local patch_done_name="$patch_name.done"
	if [[ ! -e $patch_done_name ]]; then
		if [[ -f $patch_name ]]; then
			rm $patch_name || exit 1 # remove old version in case it has been since updated on the server...
		fi
		curl -4 --retry 5 $url -O --fail || echo_and_exit "unable to download patch file $url"
		echo "applying patch $patch_name"
		patch $patch_type < "$patch_name" || exit 1
		touch $patch_done_name || exit 1
		rm -f already_ran* # if it's a new patch, reset everything too, in case it's really really really new
	#else
		#echo "patch $patch_name already applied"
	fi
}

echo_and_exit() {
	echo "failure, exiting: $1"
	exit 1
}

set_pkg_config_env(){
	export PKG_CONFIG_PATH=${lib_dir}/lib/pkgconfig
}


build_with_func(){

   local lib_name="$1"
   local download_url="$2"
   local download_way="$3"
   local configure_way="$4"
   local configure_options="$5"

   if [ -f ${lib_info_dir}/${lib_name} ];then
	   echo_log "already installed ${lib_name} ..."
	   return 0
   fi

   ${download_way}  "${download_url}" ${lib_name} || exit 1
   cd ${lib_name}
		echo_log "configrue  dir as $ $(pwd)"
		${configure_way} "${configure_options}" &&
		do_make  &&
		do_make_install | tee ${lib_info_dir}/${lib_name} || (echo_log "${lib_name} install failed ... \n" && exit 1)

	   	if [[ $? -eq 0 ]]; then
	   		echo_log "${lib_name} install success ..."
	   		echo_log "-------------------------------->>>>>>"
	   		echo_log ""
	   	fi

   cd ${base_dir}

   return 0
}


build_yasm(){
	local lib_name=yasm
	local download_url="git://github.com/yasm/yasm.git"
	local download_way="do_git_checkout"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir}"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}

build_nasm(){

	local lib_name=nasm
	local download_url="https://www.nasm.us/pub/nasm/releasebuilds/2.14/nasm-2.14.tar.xz"
	local download_way="download_and_unpack_file"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir}"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}



build_x264(){
	local lib_name=x264
	local download_url="git://git.videolan.org/x264"
	local download_way="do_git_checkout"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} --enable-static "

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"
	return $?
}

build_x265(){

	local lib_name=x265
	local download_url="https://github.com/videolan/x265.git"
	local download_way="do_git_checkout"
	local configure_way=" cd build/linux && do_cmake "
	local configure_options="-DCMAKE_INSTALL_PREFIX=${lib_dir} -DENABLE_SHARED:bool=off ../../source"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}

build_fdk-aac(){

	local lib_name=fdk-aac
	local download_url="git://git.code.sf.net/p/opencore-amr/fdk-aac"
	local download_way="do_git_checkout"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} --disable-shared"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}

build_lame(){

	local lib_name=lame
	local download_url="http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz"
	local download_way="download_and_unpack_file"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} --disable-shared"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}

build_opus(){

	local lib_name=opus
	local download_url="http://git.opus-codec.org/opus.git"
	local download_way="do_git_checkout"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} --disable-shared"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}

build_ogg(){

	local lib_name=ogg
	local download_url="http://downloads.xiph.org/releases/ogg/libogg-1.3.2.tar.gz"
	local download_way="download_and_unpack_file"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} --disable-shared"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}

build_vorbis(){

	local lib_name=vorbis
	local download_url="http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.4.tar.gz"
	local download_way="download_and_unpack_file"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} --with-ogg=${lib_dir} --disable-shared"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}


build_libvpx(){

	local lib_name=libvpx
	local download_url="https://chromium.googlesource.com/webm/libvpx"
	local download_way="do_git_checkout"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} --disable-examples"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}


build_SDL2(){

	local lib_name=SDL2
	local download_url="http://www.libsdl.org/release/SDL2-2.0.5.tar.gz"
	local download_way="download_and_unpack_file"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} --disable-shared"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}


build_numactl(){

	local lib_name=numactl
	local download_url="https://github.com/numactl/numactl.git"
	local download_way="do_git_checkout"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} -enable-shared=no"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}


build_libiconv(){

	local lib_name=libiconv
	local download_url="https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.12.tar.gz"
	local download_way="download_and_unpack_file"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} -enable-static=yes --enable-shared=no "

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}

build_libpng(){

	local lib_name=libpng
	local download_url="https://github.com/glennrp/libpng.git"
	local download_way="do_git_checkout"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir} --enable-shared=no "

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}

build_zvbi(){

	local lib_name=zvbi
	local download_url="https://nchc.dl.sourceforge.net/project/zapping/zvbi/0.2.35/zvbi-0.2.35.tar.bz2"
	local download_way="download_and_unpack_file"
	local configure_way="do_configure"
	local configure_options="--prefix=${lib_dir}  --enable-shared=no "

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}"  "${configure_options}"

	return $?
}


build_ffmpeg(){

	local lib_name=ffmpeg
	local download_url="http://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2"
	local download_way="download_and_unpack_file"
	local configure_way="do_configure"

	local configure_options="--prefix=${build_dir}
							--enable-pic
                            --disable-optimizations
                            --enable-debug=3
							--pkg-config-flags=--static
							--pkg-config=pkg-config
							--extra-ldexeflags=-static
							--enable-gpl --enable-nonfree --enable-libfdk_aac
							--enable-libx264
                            --disable-libvpx
                            --disable-iconv
                            --disable-libmp3lame
                            --disable-libvorbis
                            "
                            
                        #   --enable-iconv
						#	--enable-libmp3lame
						#	--enable-libopus --enable-libvorbis
						#	--enable-libvpx --enable-libx264
						#	--enable-libzvbi
						#	--extra-libs='-L${lib_dir}/lib -lpng'
						#	--enable-libx265"

	build_with_func "${lib_name}" "${download_url}" "${download_way}" "${configure_way}" "${configure_options}"

	return $?
}

parse_arguments $*

# check_need_tools

set_pkg_config_env

build_yasm &&
build_nasm &&
build_x264 &&
build_x265 &&
build_fdk-aac &&
build_lame &&
build_opus &&
build_ogg &&
build_vorbis &&
build_libvpx &&
# build_SDL2 &&
build_numactl &&
# build_libiconv &&
# build_libpng &&
build_zvbi &&
build_ffmpeg
