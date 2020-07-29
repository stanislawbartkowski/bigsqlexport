source resource.rc

OUTPUTDB2DLL=$OUTPUTALLDIR/db2dll.sql
OUTPUTALLDLL=$OUTPUTALLDIR/alldll.sql
OUTPUTALLGRANT=$OUTPUTALLDIR/allgrant.sql

log() {
    echo "$1"
}

logfail() {
    echo "$1"
    echo "Failed, cannot continue"
    exit 1
}

preparedb2look() {
    if [ -z $USERID ]; then 
        DB2LOOK="db2look -d $DBNAME"
    else
        DB2LOOK="db2look -d $DBNAME -i $USERID -w $PASSWORD"
    fi

}

exportalldll() {
    local -r TMP=`mktemp`
    mkdir -p $OUTPUTALLDIR
    rm -f $OUTPUTALLDLL
    rm -f $OUTPUTALLGRANT
    log "Export all DLLs for schemas $SCHEMAS to $OUTPUTALLDLL and $OUTPUTALLGRANT"
    for s in $SCHEMAS ; do 
        log "Export DLL for schema $s"
        $DB2LOOK -z $s -x -e  -o $TMP
        [ $? -eq 0 ] || logfail "db2look for schema failed"
        cat $TMP >>$OUTPUTALLDLL
        $DB2LOOK -z $s -xd -o $TMP
        [ $? -eq 0 ] || logfail "db2look for grant failed"
        cat $TMP >>$OUTPUTALLGRANT
    done
    rm $TMP
    log "Exporting DLL to $OUTPUTALLDLL completed"
}

connect() {
    if [ -z $USERID ]; then 
        db2 connect to $DBNAME
    else
        db2 connect to $DBNAME user $USERID using $PASSWORD
    fi
    [ $? -eq 0 ] || logfail "Cannot connect"
}

terminate() {
    db2 terminate
}

selectdb2tables() {
    local -r TMP=$1
    connect
    db2 -x -z $TMP "select rtrim(tabschema) || '.' || tabname from syscat.tables where tbspaceid > 1 and tbspace <> 'SYSTOOLSPACE'" 
    [ $? -eq 0 ] || logfail "Query failed"
    terminate
}

exportdb2dll() {
    mkdir -p $OUTPUTALLDIR
    rm -f $OUTPUTDB2DLL
    log "Export DB2 managed tables to $OUTPUTDB2DLL"
    local -r TMP=`mktemp`
    local -r TMP1=`mktemp`
    selectdb2tables $TMP
    while read -r line; do 
        log "Export DLL for $line"
        $DB2LOOK -t $line -x -e -o $TMP1
        [ $? -eq 0 ] || logfail "db2look failed"
        cat $TMP1 >>$OUTPUTDB2DLL
        [ $? -eq 0 ] || logfail "Cannot concatenate the result: cat $TMP1 >>$OUTPUTDB2DLL"
    done <$TMP    
    log "Exporting DB2 managed DLLs to $OUTPUTDB2DLL completed"
    rm $TMP
    rm $TMP1
}

exportdb2tables() {
    log "Export DB2 tables to $OUTPUTDIR"
    rm -rf $OUTPUTDIR
    mkdir -p $OUTPUTDIR    
    local -r TMP=`mktemp`
    selectdb2tables $TMP
    connect
    while read -r line; do 
        log "Export table $line to $OUTPUTDIR/$line.ixf"
        db2 "export to $OUTPUTDIR/$line.ixf of ixf messages $OUTPUTDIR/$line.msg select * from $line"
        [ $? -eq 0 ] || logfail "Export failed"
    done <$TMP
    terminate
    rm $TMP
    log "Export DB2 managed tables to $OUTPUTDIR completed."
}

importdb2dll() {
    log "Import DB2 DLL from $OUTPUTDB2DLL"
    connect
    db2 -tvf $OUTPUTDB2DLL
    [ $? -eq 0 ] || logfail "Import from $OUTPUTDB2DLL  failed"
    terminate
}

importdb2tables() {
    log "Import DB2 tables from $OUTPUTDIR"
    connect
    for file in $OUTPUTDIR/*.ixf ; do
        TABLE=`basename $file .ixf`
        MESS="${file%.*}".mess
        log "Import $TABLE from $file"
#        db2 load $CLIENT from $file of ixf replace into $TABLE
        echo "db2 import from $file of ixf messages $MESS replace into $TABLE"
        db2 import from $file of ixf messages $MESS replace into $TABLE
        [ $? -eq 0 ] || logfail "Load $TABLE failed"
    done
    terminate
    log "Import DB2 tables from $OUTPUTDIR completed"
}

printhelp() {
    echo "export.sh /action/"
    echo   "all : Export all dlls for schemas $SCHEMA"
    echo   "db2 : Export dlls for tables managed by DB2"
    echo   "db2tables: Export DB2 tables managed to DB2"
    echo   "db2importdll: Import DLL exported by db2"
    echo   "db2importtables: Import tables assuming DLL already imported"
}

preparedb2look

case $1 in
    all) exportalldll;;
    db2) exportdb2dll;;
    db2tables) exportdb2tables;;
    db2importdll) importdb2dll;;
    db2importtables) importdb2tables;;
    *) printhelp;;
esac