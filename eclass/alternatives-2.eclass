# Copyright 2010-2014 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

# Based in part upon 'alternatives.exlib' from Exherbo, which is:
# Copyright 2008, 2009 Bo Ørsted Andresen
# Copyright 2008, 2009 Mike Kelly
# Copyright 2009 David Leverton

# If your package provides pkg_postinst or pkg_prerm phases, you need to be
# sure you explicitly run alternatives_pkg_{postinst,prerm} where appropriate.

ALTERNATIVES_DIR="/etc/env.d/alternatives"

DEPEND=">=app-admin/eselect-1.4-r100"
RDEPEND="${DEPEND}
	!app-admin/eselect-blas
	!app-admin/eselect-cblas
	!app-admin/eselect-lapack"

EXPORT_FUNCTIONS pkg_postinst pkg_prerm

# alternatives_for alternative provider importance source target [ source target [...]]
alternatives_for() {

	(( $# >= 5 )) && (( ($#-3)%2 == 0)) || die "${FUNCNAME} requires exactly 3+N*2 arguments where N>=1"
	local alternative=${1} provider=${2} importance=${3} index src target ret=0
	shift 3

	# make sure importance is a signed integer
	if [[ -n ${importance} ]] && ! [[ ${importance} =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
		eerror "Invalid importance (${importance}) detected"
		((ret++))
	fi

	[[ -d "${ED}${ALTERNATIVES_DIR}/${alternative}/${provider}" ]] || dodir "${ALTERNATIVES_DIR}/${alternative}/${provider}"

	# keep track of provided alternatives for use in pkg_{postinst,prerm}. keep a mapping between importance and
	# provided alternatives and make sure the former is set to only one value
	if ! has "${alternative}:${provider}" "${ALTERNATIVES_PROVIDED[@]}"; then
		index=${#ALTERNATIVES_PROVIDED[@]}
		ALTERNATIVES_PROVIDED+=( "${alternative}:${provider}" )
		ALTERNATIVES_IMPORTANCE[index]=${importance}
		[[ -n ${importance} ]] && echo "${importance}" > "${ED}${ALTERNATIVES_DIR}/${alternative}/${provider}/_importance"
	else
		for((index=0;index<${#ALTERNATIVES_PROVIDED[@]};index++)); do
			if [[ ${alternative}:${provider} == ${ALTERNATIVES_PROVIDED[index]} ]]; then
				if [[ -n ${ALTERNATIVES_IMPORTANCE[index]} ]]; then
					if [[ -n ${importance} && ${ALTERNATIVES_IMPORTANCE[index]} != ${importance} ]]; then
						eerror "Differing importance (${ALTERNATIVES_IMPORTANCE[index]} != ${importance}) detected"
						((ret++))
					fi
				else
					ALTERNATIVES_IMPORTANCE[index]=${importance}
					[[ -n ${importance} ]] && echo "${importance}" > "${ED}${ALTERNATIVES_DIR}/${alternative}/${provider}/_importance"
				fi
			fi
		done
	fi

	while (( $# >= 2 )); do
		src=${1//+(\/)/\/}; target=${2//+(\/)/\/}
		if [[ ${src} != /* ]]; then
			eerror "Source path must be absolute, but got ${src}"
			((ret++))

		else
			local reltarget= dir=${ALTERNATIVES_DIR}/${alternative}/${provider}${src%/*}
			while [[ -n ${dir} ]]; do
				reltarget+=../
				dir=${dir%/*}
			done

			reltarget=${reltarget%/}
			[[ ${target} == /* ]] || reltarget+=${src%/*}/
			reltarget+=${target}
			dodir "${ALTERNATIVES_DIR}/${alternative}/${provider}${src%/*}"
			dosym "${reltarget}" "${ALTERNATIVES_DIR}/${alternative}/${provider}${src}"

			# say ${ED}/sbin/init exists and links to /bin/systemd (which doesn't exist yet)
			# the -e test will fail, so check for -L also
			if [[ -e ${ED}${src} || -L ${ED}${src} ]]; then
				local fulltarget=${target}
				[[ ${fulltarget} != /* ]] && fulltarget=${src%/*}/${fulltarget}
				if [[ -e ${ED}${fulltarget} || -L ${ED}${fulltarget} ]]; then
					die "${src} defined as provider for ${fulltarget}, but both already exist in \${ED}"
				else
					mv "${ED}${src}" "${ED}${fulltarget}" || die
				fi
			fi
		fi
		shift 2
	done

	[[ ${ret} -eq 0 ]] || die "Errors detected for ${provider}, provided for ${alternative}"
}

cleanup_old_alternatives_module() {
	local alt=${1} old_module="${EROOT%/}/usr/share/eselect/modules/${alt}.eselect"
	if [[ -f "${old_module}" && "$(source "${old_module}" &>/dev/null; echo "${ALTERNATIVE}")" == "${alt}" ]]; then
		local version="$(source "${old_module}" &>/dev/null; echo "${VERSION}")"
		if [[ "${version}" == "0.1" || "${version}" == "20080924" ]]; then
			echo rm "${old_module}"
			rm "${old_module}" || eerror "rm ${old_module} failed"
		fi
	fi
}

alternatives-2_pkg_postinst() {
	local a alt provider module_version="20090908"
	local EAUTO="${EROOT%/}/usr/share/eselect/modules/auto"
	for a in "${ALTERNATIVES_PROVIDED[@]}"; do
		alt="${a%:*}"
		provider="${a#*:}"
		if [[ ! -f "${EAUTO}/${alt}.eselect" \
			|| "$(source "${EAUTO}/${alt}.eselect" &>/dev/null; echo "${VERSION}")" \
				-ne "${module_version}" ]]; then
			if [[ ! -d ${EAUTO} ]]; then
				install -d "${EAUTO}" || eerror "Could not create eselect modules dir"
			fi
			cat > "${EAUTO}/${alt}.eselect" <<-EOF
				# This module was automatically generated by alternatives.eclass
				DESCRIPTION="Alternatives for ${alt}"
				VERSION="${module_version}"
				MAINTAINER="eselect@gentoo.org"
				ESELECT_MODULE_GROUP="Alternatives"

				ALTERNATIVE="${alt}"

				inherit alternatives
			EOF
		fi

		einfo "Creating ${provider} alternative module for ${alt}"
		eselect "${alt}" update "${provider}"

		cleanup_old_alternatives_module ${alt}
	done
}

alternatives-2_pkg_prerm() {
	local a alt provider ignore
	local EAUTO="${EROOT%/}/usr/share/eselect/modules/auto"
	[[ -n ${REPLACED_BY_ID} ]] || ignore=" --ignore"
	for a in "${ALTERNATIVES_PROVIDED[@]}"; do
		alt="${a%:*}"
		provider="${a#*:}"
		eselect "${alt}" update${ignore} "${provider}" && continue
		einfo "Removing ${provider} alternative module for ${alt}, current is $(eselect ${alt} show)"
		case $? in
			0) : ;;
			2)
				einfo "Cleaning up unused alternatives module for ${alt}"
				rm "${EAUTO}/${alt}.eselect" || \
					eerror rm "${EAUTO}/${alt}.eselect" failed
				;;
			*)
				eerror eselect "${alt}" update "${provider}" returned $?
				;;
		esac
	done
}
