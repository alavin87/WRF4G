#! /bin/bash
#
# WRF4G_ini.sh
#
# WRF4G initializer
#
ROOTDIR=$(pwd)
#
#   Expand the sandbox files
#
tar xzf sandbox.tar.gz
#
#  Load wrf.input and wrf.chunk
#
source wrf4g.conf                            || exit ${ERROR_MISSING_WRF4GCNF}
sed -e 's/\ *=\ */=/' wrf.input > source.it  || exit ${ERROR_MISSING_WRFINPUT}
source source.it && rm source.it
sed -e 's/\ *=\ */=/' wrf.chunk > source.it  || exit ${ERROR_MISSING_WRFCHUNK}
source source.it && rm source.it
#
#   Expand the WRF4G scripts
#
export PATH="${ROOTDIR}/bin:$PATH"
chmod +x ${ROOTDIR}/bin/*
vcp ${WRF4G_APPS}/WRF4G-${WRF4G_VERSION}.tar.gz . || exit ${ERROR_MISSING_WRF4GSRC}
tar xzf WRF4G-${WRF4G_VERSION}.tar.gz && rm -f WRF4G-${WRF4G_VERSION}.tar.gz
#
#  Load functions and set the PATH
#
source ${ROOTDIR}/lib/bash/wrf_util.sh
source ${ROOTDIR}/lib/bash/wrf4g_exit_codes.sh
export PATH="${ROOTDIR}/WRFGEL:$PATH"
chmod +x ${ROOTDIR}/WRFGEL/*

function w4gini_exit(){
  excode=$1
  case ${excode} in
    ${ERROR_GETDATERST_FAILED})
      echo "Problems getting the restart date... (not even -1)"
      ;;
    ${EXIT_CHUNK_ALREADY_FINISHED})
      echo "This chunk already run! Ciao..." >> WRF4G_ini.err
      ;;
    ${EXIT_RESTART_MISMATCH})
      echo "Something went wrong! (the restart file is not available and the chunk is a restart...)" >> WRF4G_ini.err
      ;;
    ${EXIT_CHUNK_SHOULD_NOT_RUN})
      echo "The date of the simulation did not reach this chunk yet! Ciao..." >> WRF4G_ini.err
      ;;
    ${ERROR_MISSING_WRF4GBIN})
      echo "Could not find the WRF binary file: WRF4Gbin-${WRF_VERSION}.tar.gz " >> WRF4G_ini.err
      ;;
  esac
  exit ${excode}
}
#
#   Should we unpack here or there is a local filesystem for us to run?
#
if test -n "${WRF4G_RUN_LOCAL}"; then
  if test "${WRF4G_RUN_LOCAL:0:4}" = "var:" ; then
    eval "WRF4G_RUN_LOCAL=\$$(echo ${WRF4G_RUN_LOCAL} | sed -e 's/var://')"
  fi
  LOCALDIR="${WRF4G_RUN_LOCAL}/wrf4g.$(date +%Y%m%d%H%M%S%N)"
  mkdir ${LOCALDIR} || exit ${ERROR_CANNOT_ACCESS_LOCALDIR}
fi
#
#  Should this chunk REALLY run?
#
set -v
export WRF4G_CONF_FILE="${ROOTDIR}/wrf4g.conf"
export WRF4G_EXPERIMENT="${experiment_name}"
export WRF4G_REALIZATION="${realization_name}"
if test ${is_restart} -eq 1; then
  echo "This is a forced-restart run" >> WRF4G_ini.out
  # This will make the trick...
  restart_date=$(date_wrf2iso ${chunk_start_date})
else
  restart_date=$(get_date_restart -v || w4gini_exit ${ERROR_GETDATERST_FAILED})
  echo "Last restart date for this realization is ${restart_date}" >> WRF4G_ini.out
fi
current_date=$(get_date_current)
echo "Current date for this realization is ${current_date}" >> WRF4G_ini.out
if test "$(date2int ${current_date})" -ge "$(date2int ${chunk_end_date})"; then
  if test ${is_continuous} -eq 1 \
       -a $(date2int ${current_date}) -ne $(date2int ${end_date}) \
       -a ${restart_date} -ne "-1" \
       -a $(date2int ${restart_date}) -lt $(date2int ${chunk_end_date}) ; then
    #
    #  If this is a continuous run and this realization did not reach the end
    #  and there is no restart file for a date at least as late the end of this
    #  chunk, there is no way for the next chunk to continue, so we should
    #  pitifully repeat this chunk to get the restart file. So, go ahead and
    #  simulate!
    #
    echo "Pitifully repeating this finished chunk (restart file missing at the end)"
    echo "chunk_restart_date=\"$(date_iso2wrf ${restart_date})\"" >> wrf.chunk
  else
    test -n "${LOCALDIR}" && rmdir ${LOCALDIR}
    w4gini_exit ${EXIT_CHUNK_ALREADY_FINISHED}
  fi
elif test "${restart_date}" = "-1"; then
  if test "${chunk_is_restart}" = ".T."; then
    test -n "${LOCALDIR}" && rmdir ${LOCALDIR}
    w4gini_exit ${EXIT_RESTART_MISMATCH}
  fi
  echo "chunk_restart_date=\"${chunk_start_date}\"" >> wrf.chunk
elif test "$(date2int ${restart_date})" -lt "$(date2int ${chunk_start_date})"; then
  test -n "${LOCALDIR}" && rmdir ${LOCALDIR}
  w4gini_exit ${EXIT_CHUNK_SHOULD_NOT_RUN}
else
  #
  #  Set the restart flag to true and set the new start date
  #
  if test "$(date2int ${restart_date})" -ne "$(date2int ${chunk_start_date})"; then
    echo 'chunk_is_restart=".T."' >> wrf.chunk
  fi
  echo "chunk_restart_date=\"$(date_iso2wrf ${restart_date})\"" >> wrf.chunk
fi
#######################################################################
#
#  IF YOU GOT HERE, WE ARE RUNNING THIS CHUNK
#
#######################################################################
#
#  Reload the modified wrf.chunk and copy it to the local directory if necessary
#
sed -e 's/\ *=\ */=/' wrf.chunk > source.it  || exit ${ERROR_MISSING_WRFCHUNK}
source source.it && rm source.it
test -n "${LOCALDIR}" && cp wrf.chunk ${LOCALDIR}/
#
#  Get the restart files, if this is a restart
#
if test ${chunk_is_restart} = ".T."; then
  test -n "${LOCALDIR}" && cd ${LOCALDIR}
    download_file rst ${restart_date} || exit ${ERROR_RST_DOWNLOAD_FAILED}
  test -n "${LOCALDIR}" && cd ${ROOTDIR}
fi
set +v
#
#  Create WRF4G framework structure
#
test -n "${LOCALDIR}" && cd ${LOCALDIR}
mkdir -p log
vcp ${WRF4G_APPS}/WRF4Gbin-${WRF_VERSION}.tar.gz .
tar xzf WRF4Gbin-${WRF_VERSION}.tar.gz && rm -f WRF4Gbin-${WRF_VERSION}.tar.gz || w4gini_exit ${ERROR_MISSING_WRF4GBIN}
tar xzf ${ROOTDIR}/sandbox.tar.gz WRFV3/run/namelist.input # La namelist buena esta aqui!
mv wrfrst* WRFV3/run >& /dev/null || :
rm -f ${ROOTDIR}/sandbox.tar.gz 
echo ${ROOTDIR} > rootdir
echo "${HOSTNAME}:${PWD}" > ${ROOTDIR}/localdir
#
#  If there are additional files, expand'em
#
if test -f ${ROOTDIR}/wrf4g_files.tar.gz; then
  tar xzvf ${ROOTDIR}/wrf4g_files.tar.gz && rm ${ROOTDIR}/wrf4g_files.tar.gz
fi
#
#   Now run the WRF4G...
#
source ${ROOTDIR}/WRF4G.sh >& log/WRF4G.log
