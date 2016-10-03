#!/bin/ksh
# ////////////////////////////////////////////////////////////////////////////////
# // Empresa: BBVA
# // Autor:   Equipo IyP: Ingenieria y Proyectos Middleware
# // SSOO: Linux
# // Script para arrancar, parar o listar las instancias de JBOSS
# //
# // Uso:
# // jboss.sh [stop|start|restart|info] [all|services|cluster_name|instace_name]
# // Fecha: Noviembre 2014
# // Revision: Febrero 2015
# ////////////////////////////////////////////////////////////////////////////////

# Se cargan las variables de entorno y globales de Jboss
. /MIDDLEWARE/uti/conf/entorno.conf
. /usr /local/pr/jboss/BBVA/global_jboss.conf
FECHA=`date +"%Y-%m-%d"`
logFILE="/MIDDLEWARE/uti/logs/jboss.log.$FECHA"

## FUNCION LOG
log(){
# Escribe en $logFILE el mensaje formateado $1
HORA=`date +"%d/%m/%Y-%H:%M:%S"`
if [ ! -f $logFILE ]
then
        umask 000
    touch $logFILE
fi
    echo "$HORA $USER $1" |tee -a $logFILE
}

## FUNCION ERRORLOG
errorlog(){
RESULT=$?
if [ $RESULT -ne 0 ]
then
        log "ERROR: Se ha producido un error en la ejecucion de la tarea"
    log "INFO: Ejecucion finalizada."
    exit $RESULT
fi
}

## FUNCION PARAR
parar() {
case ${OBJETO} in

        "all" ) log "INFO: PARANDO TODO JBOSS";
                kill -9 `ps -ef|grep ${JBOSS_HOME}|grep ${JBOSS_USER}|grep -v grep| awk '{print $2}'` 2>/dev/null;
        errorlog;
        log "INFO: PARADO TODO JBOSS";;

        "services" ) log "INFO: PARANDO TODOS LOS SERVERGROUPS DE SERVICIOS";
                export SERVICIOS="SRVS"
                NUM_PROC=`ps -ef|grep ${JBOSS_HOME}|grep ${JBOSS_USER}|grep ${SERVICIOS}|grep -v grep|wc -l`
            if [ $NUM_PROC -ge 1 ]
            then
                        kill -9 `ps -ef|grep ${JBOSS_HOME}|grep ${JBOSS_USER}|grep ${SERVICIOS}|grep -v grep|awk '{print $2}'` 2>/dev/null;
            errorlog;
            log "INFO: PARADO ${OBJETO} COMPLETAMENTE";
        else
                        log "INFO: Instancia: ${OBJETO} no arrancada o inexistente";
            fi
            ;;

        * ) log "INFO: PARANDO ${OBJETO} COMPLETAMENTE";
                NUM_PROC=`ps -ef|grep ${JBOSS_HOME}|grep ${JBOSS_USER}|grep ${OBJETO}|grep -v grep|wc -l`
            if [ $NUM_PROC -ge 1 ]
            then
                        kill -9 `ps -ef|grep ${JBOSS_HOME}|grep ${JBOSS_USER}|grep ${OBJETO}|grep -v grep|awk '{print $2}'` 2>/dev/null;
            errorlog;
            log "INFO: PARADO ${OBJETO} COMPLETAMENTE";
        else
                        log "INFO: Instancia: ${OBJETO} no arrancada o inexistente";
        fi
        ;;
esac
}

# NOTA:Todos los arranques pasan por aqui. Tanto ${INSTANCIA} como ${SERVERGROUP}
## FUNCION arrancar instancia
arrancar_instancia() {

        export INSTANCIA="$1"
        # Cargamos nuevamente las variables
        . ${SERVERGROUPCONFIG}
        export OFFSET_BASE="$2"

        # Comprobacion de contenido variable offset base
        if [[ X$OFFSET_BASE == X ]]
        then
            export OFFSET_BASE=`echo ${OFFSET}`
        fi

        # Comprobacion de uso Dynatrace. Es obligatorio para correcta asignacion de JAVA_OPTS (incidencia)
        if [[ ${MONITOR_AGENT} == *libdtagent.so* ]]
    then
            export JAVA_OPTS="${MONITOR_AGENT}_${INSTANCIA} ${JAVA_OPTS}"
    else
        export JAVA_OPTS="${MONITOR_AGENT}  ${JAVA_OPTS}"
        fi
    log "INFO: ARRANCANDO ${INSTANCIA}"
        CLONID=`echo $INSTANCIA|awk -F'_' '{print $NF}'`
        HOST_INS=`echo $INSTANCIA|awk -F'_' '{print $1}'`

        # Obtenemos el ultimo digito del CLONID
        SUB_CLONID=`awk ' END { print substr(sstr,2,1) }' "sstr=$CLONID" /dev/null `

        # Calculamos el OFFSET para los arranques individuales de instancias: offset + ultimo digito clonID
        OFFSET=`echo $((OFFSET_BASE + $SUB_CLONID))`

        # Calculamos el IMSID
        export CLONID=`echo $INSTANCIA|awk -F'_' '{print $NF}'`
        case "$CLONID" in
                *([0-9]))
                        ;;

                *) log "ERROR: ERROR NOMBRE DE INSTANCIA ERRÓNEO"
                        exit -1
                        ;;
        esac
        export MAQUINA=`echo ${HOSTNAME}|tr [a-z] [A-Z]`
        export INSTANCIA=${MAQUINA}_${SERVERGROUP}_${CLONID}
        # Se calcula en base 38 por tener el mayo rango posible, y para evitar la insercion del caracter eñe.
        typeset -i38 port
        # Cuidado. El calculo de IMSID esta pensado para rangos de puertos de siete miles. Pueden darse casos de duplicidades con rangos ajenos. TENER EN CUENTA HTTP_PORT.
        export port=`echo $((HTTP_PORT + OFFSET - 7000))`
        export PORT=`echo ${port}|cut -d"#" -f2`
        export IMSID=${C}${HH}${PORT}

        # Comprobacion de PID de proceso
        PID=`ps -ef|grep ${JBOSS_HOME}|grep ${INSTANCIA}|grep -v grep|awk '{print $2}'`
        if [ "$PID" = "" ]
    then
                # Arranque de la instancia
        TMP_PATH="`dirname ${SERVERGROUPCONFIG}`/tmp/${INSTANCIA}/"
        # Borramos temporales solo en arranques completos del servergroup
        log "INFO: Borrando ficheros temporales de ${TMP_PATH}"
        rm -rf ${TMP_PATH}/*
        ${JBOSS_HOME}/bin/standalone.sh -Djboss.server.name=${INSTANCIA} -DcloneId=${CLONID} -DimsID=${IMSID} --server-config=${SERVERGROUP}.xml -Djboss.server.temp.dir=${TMP_PATH} >> ${LOG_PATH}/${INSTANCIA}/${INSTANCIA}.log 2>&1 &
        errorlog;
        log "INFO: ARRANCADO ${INSTANCIA}"
        log "INFO: Puede mirar las trazas en ${LOG_PATH}/${INSTANCIA}/${INSTANCIA}.log"
    else
        log "INFO: La Instancia ${SERVERGROUPCONFIG} ya estaba iniciada"
        fi
}

## FUNCION arrancar instancia/servergroup
arrancar_servergroup() {

        SERVERGROUPCONFIG=$1
        unset MAX_NUMBER_OF_SERVERS OFFSET JAVA_OPTS
        export RUN_CONF="disable"

        # Se cargan nuevamente las variables incluidas en global (Resolucion de incidencia)
        . /usr/local/pr/jboss/BBVA/global_jboss.conf
        . ${SERVERGROUPCONFIG}
        DATA_PATH="`dirname ${SERVERGROUPCONFIG}`/data/"

        # Iteramos hasta llegar al MAX_NUMBER_OF_SERVERS, ajustando OFFSET, CLONEID y calculo imsID
        COUNTER=1
        export OFFSET_PLANTILLA_CONF=`echo ${OFFSET}`
        while [[ $COUNTER -le ${MAX_NUMBER_OF_SERVERS} ]];
    do
                export CLONID=`echo $((COUNTER + 9))`
        export MAQUINA=`echo ${HOSTNAME}|tr [a-z] [A-Z]`
        export INSTANCIA=${MAQUINA}_${SERVERGROUP}_${CLONID}
        arrancar_instancia ${INSTANCIA} ${OFFSET_PLANTILLA_CONF}
        export COUNTER=`echo $((COUNTER + 1))`
        done;

        if [ "0${MAX_NUMBER_OF_SERVERS}" == "0" ]
        then
                log "INFO: No se ha iniciado la instancia ${INSTANCIA}, porque el MAX_NUMBER_OF_SERVERS=0"
        fi
}

## FUNCION arrancar
arrancar() {

        cod_return=0
        case $OBJETO in

        "all" )
                log "INFO: ARRANCANDO TODO JBOSS";

        # generacion de modulos
        if [ $? == 0 ]
        then
            log "INFO: Ejecucion de arranque correcta. Se ejecuta la actualizacion de modulos"
            log "INFO: Puedes revisar los logs en la ruta: /MIDDLEWARE/uti/logs/modules.log.$FECHA"
        # Ejecucion de actualizacion de modulos
            `/MIDDLEWARE/uti/scrt/generateModule.bash` 2>/dev/null;
        fi
                for SERVERGROUPCONFIG in `find $BBVA_CONFIG_DIR -name "????_[A-Z][0-9][0-9].conf"`
        do
                        arrancar_servergroup ${SERVERGROUPCONFIG}
        done;;

        "services" )
                log "INFO: ARRANCANDO TODAS LAS INSTANCIAS JBOSS DE SERVICIOS";

        # generacion de modulos
        if [ $? == 0 ]
        then
            log "INFO: Ejecucion de arranque correcta. Se ejecuta la actualizacion de modulos"
            log "INFO: Puedes revisar los logs en la ruta: /MIDDLEWARE/uti/logs/modules.log.$FECHA"
        # Ejecucion de actualizacion de modulos
            `/MIDDLEWARE/uti/scrt/generateModule.bash` 2>/dev/null;
        fi
                for SERVERGROUPCONFIG in `find $BBVA_CONFIG_DIR -name "SRVS_[A-Z][0-9][0-9].conf"`
        do
                        arrancar_servergroup ${SERVERGROUPCONFIG}
        done;;

       # Comprobacion si es cluster; afirmativo: ejecucion arrancar_cluster. Negativo o instancia individual: recarga variables (incidencia)

        * )
        if [ -f ${BBVA_CONFIG_DIR}/SERVERGROUPS/${OBJETO}/${OBJETO}.conf ]
        then
                        log "INFO: ARRANCANDO SERVERGROUP ${OBJETO}"
            arrancar_servergroup ${BBVA_CONFIG_DIR}/SERVERGROUPS/${OBJETO}/${OBJETO}.conf
        else
            log "INFO: ARRANCANDO INSTANCIA ${OBJETO}"
            GRUPO_SERV=`echo ${OBJETO} |  awk -F_ '{print $2"_"$3}'`
            SERVERGROUPCONFIG=${BBVA_CONFIG_DIR}/SERVERGROUPS/${GRUPO_SERV}/${GRUPO_SERV}.conf
            unset MAX_NUMBER_OF_SERVERS OFFSET JAVA_OPTS
            export RUN_CONF="disable"
            . /usr/local/pr/jboss/BBVA/global_jboss.conf
            . ${SERVERGROUPCONFIG}
            arrancar_instancia ${OBJETO}
                fi

        esac
        return $cod_return
}

restart() {

        log "RESTART";
                export SERVICIOS="SRVS"
        case ${OBJETO} in

    "all" )  log "INFO: PARANDO TODO JBOSS";
        kill -9 `ps -ef|grep ${JBOSS_HOME}|grep -v grep| awk '{print $2}'` 2>/dev/null;
        # Si falla al hacer el kill
        RESULT=$?
        if [ $RESULT -ne 0 ]
        then
                # preguntamos si hay algun pid con filtrando por el nombre del grupo de servidores
                        PID=`ps -ef|grep ${JBOSS_HOME}|grep -v grep | awk '{print $2}'`;
            if [ "$PID" != "" ]
            then
                                log "ERROR: No se ha podido finalizar el proceso $PID"
                log "INFO: Ejecucion finalizada."
                exit -1
                        fi
                fi
                log "INFO: PARADO TODO JBOSS";
                # generacion de modulos
        if [ $? == 0 ]
        then
            log "INFO: Ejecucion de arranque correcta. Se ejecuta la actualizacion de modulos"
            log "INFO: Puedes revisar los logs en la ruta: /MIDDLEWARE/uti/logs/modules.log.$FECHA"
        # Ejecucion de actualizacion de modulos
            `/MIDDLEWARE/uti/scrt/generateModule.bash` 2>/dev/null;
        fi
        log "INFO: ARRANCANDO TODO JBOSS";

        for SERVERGROUPCONFIG in `find $BBVA_CONFIG_DIR -name "????_[A-Z][0-9][0-9].conf"`
        do
                        arrancar_servergroup ${SERVERGROUPCONFIG}
        done;;

        "services" ) log "INFO: PARANDO TODAS LAS INSTANCIAS DE JBOSS SERVICES";

                export SERVICIOS="SRVS"
        NUM_PROC=`ps -ef|grep ${JBOSS_HOME}|grep ${JBOSS_USER}|grep ${SERVICIOS}|grep -v grep|wc -l`
        if [ $NUM_PROC -ge 1 ]
        then
                        kill -9 `ps -ef|grep ${JBOSS_HOME}|grep ${JBOSS_USER}|grep ${SERVICIOS}|grep -v grep|awk '{print $2}'` 2>/dev/null;
            errorlog;
            log "INFO: PARADO ${OBJETO} COMPLETAMENTE";
            # Si falla al hacer el kill
            RESULT=$?
            if [ $RESULT -ne 0 ]
            then
                                # preguntamos si hay algun pid con filtrando por el nombre del grupo de servidores
                PID=`ps -ef|grep ${JBOSS_HOME}|grep ${SERVICIOS}|grep -v grep|awk '{print $2}'` 2>/dev/null;
                if [ "$PID" != "" ]
                then
                                        log "ERROR: No se ha podido finalizar el proceso $PID"
                    log "INFO: Ejecucion finalizada."
                    exit -1
                else
                                        log "INFO: Parece que el server ${OBJETO} ya estaba Parado."
                fi
                        fi
            log "INFO: PARADO ${OBJETO} COMPLETAMENTE";
        fi
        if [ $? == 0 ]
        then
                        log "INFO: Ejecucion de arranque correcta. Se ejecuta la actualizacion de modulos"
                log "INFO: Puedes revisar los logs en la ruta: /MIDDLEWARE/uti/logs/modules.log.$FECHA"
            # Ejecucion de actualizacion de modulos
            `/MIDDLEWARE/uti/scrt/generateModule.bash` 2>/dev/null;
                fi

        # Arranque de los servergroups de servicios
        for SERVERGROUPCONFIG in `find $BBVA_CONFIG_DIR -name "SRVS_[A-Z][0-9][0-9].conf"`
        do
                    arrancar_servergroup ${SERVERGROUPCONFIG}
        done
        ;;

        * ) log "INFO: PARANDO ${OBJETO} COMPLETAMENTE";
        kill -9 `ps -ef|grep ${JBOSS_HOME}|grep ${OBJETO}|grep -v grep|awk '{print $2}'` 2>/dev/null;
        # Si falla al hacer el kill
        RESULT=$?
        if [ $RESULT -ne 0 ]
                    then
            # preguntamos si hay algun pid con filtrando por el nombre del grupo de servidores
            PID=`ps -ef|grep ${JBOSS_HOME}|grep ${OBJETO}|grep -v grep|awk '{print $2}'` 2>/dev/null;
            if [ "$PID" != "" ]
                    then
                            log "ERROR: No se ha podido finalizar el proceso $PID"
                log "INFO: Ejecucion finalizada."
                exit -1
            else
                log "INFO: Parece que el server ${OBJETO} ya estaba Parado."
            fi
        fi
        log "INFO: PARADO ${OBJETO} COMPLETAMENTE";

        # Comprobacion si es cluster; afirmativo: ejecucion arrancar_cluster. Negativo o instancia individual: recarga variables (incidencia)
        if [ -f ${BBVA_CONFIG_DIR}/SERVERGROUPS/${OBJETO}/${OBJETO}.conf ]
                        then
            log "INFO: ARRANCANDO SERVERGROUP ${OBJETO}"
            arrancar_servergroup ${BBVA_CONFIG_DIR}/SERVERGROUPS/${OBJETO}/${OBJETO}.conf
            else
                    log "INFO: ARANCANDO INSTANCIA ${OBJETO}"
            GRUPO_SERV=`echo ${OBJETO} |  awk -F_ '{print $2"_"$3}'`
            SERVERGROUPCONFIG=${BBVA_CONFIG_DIR}/SERVERGROUPS/${GRUPO_SERV}/${GRUPO_SERV}.conf
            unset MAX_NUMBER_OF_SERVERS OFFSET JAVA_OPTS
            export RUN_CONF="disable"
            . ${SERVERGROUPCONFIG}
            arrancar_instancia ${OBJETO}
            fi;;
esac

}

## FUNCION INFO
info() {

        # Obtenemos valores de procesos
        ps -eo user,thcount,pcpu,vsz,pid,ppid,time,etime,args | grep -v grep | grep ${JBOSS_USER} | grep java| grep "jboss.server"  >> /tmp/ps.$$.tmp
        netstat -an >> /tmp/netstat.$$.tmp
        # Se imprimen los valores
        print "# - INSTANCIA\t\t\t\tPuertos\t\tRequest now\tThreads live\tMemoria vsz\tPid\t\tTime up"

        # Por cada servergroup saco su fichero de configuracion existente
        for SERVERGROUPCONF in `find ${BBVA_CONFIG_DIR}/SERVERGROUPS -name "????_???.conf" 2>/dev/null`
        do
                # Variables correspondientes al servergroup
                . ${SERVERGROUPCONF}
                COUNTER=1
                while [[ $COUNTER -le ${MAX_NUMBER_OF_SERVERS} ]];
        do
                        export CLONID=`echo $((COUNTER + 9))`
            export MAQUINA=`echo ${HOSTNAME}|tr [a-z] [A-Z]`
                export INSTANCIA=${MAQUINA}_${SERVERGROUP}_${CLONID}
            export OFFSET_LIST=`echo $(($HTTP_PORT + $OFFSET))`
            export REQ=`grep ESTABLISHED /tmp/netstat.$$.tmp|awk '{print $4}'|grep ":${OFFSET}"|wc -l `
            grep ${INSTANCIA} /tmp/ps.$$.tmp|awk -v request=$REQ -v instancia=${INSTANCIA} '{OFS = "\t\t"} {print "# - "instancia,'$OFFSET_LIST',request,$2,$4,$5,$8 }'
            (( OFFSET++ ))
            (( COUNTER++ ))
                done;
        done
        # limpiamos los registros
        rm -f /tmp/ps.$$.tmp /tmp/netstat.$$.tmp
}

cod_return=0
export USERNAME=`id -un`
if [[ "${USERNAME}" != "${JBOSS_USER}" ]]
then
        log "ERROR: Usuario de ejecucion no permitido. Se requiere usuario ${JBOSS_USER}"
    log "INFO: Ejecución finalizada."
    exit -1
else
        export ACCION=$1
    export OBJETO=$2
    case ${ACCION} in
            "stop" ) parar
                        ;;

        "start" ) arrancar
                        ;;

        "restart" ) restart
                        ;;

        "info" ) info
                        ;;

        * ) echo "OPCION NO RECONOCIDA: Sintaxis [stop|start|restart|info] [all|services|cluster_name|instace_name]";
        esac
fi
return $cod_return
