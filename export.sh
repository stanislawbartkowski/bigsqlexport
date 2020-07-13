source resource.rc

log() {
    echo "$1"
}

logfail() {
    echo "$1"
    echo "Failed, cannot continue"
    exit 1
}

exportalldll() {
    local -r TMP=`mktemp`
    mkdir -p $OUTPUTALLDIR
    local -r OUTPUTALLDLL=$OUTPUTALLDIR/alldll.sql
    local -r OUTPUTALLGRANT=$OUTPUTALLDIR/allgrant.sql
    rm -f $OUTPUTALLDLL
    rm -f $OUTPUTALLGRANT
    log "Export all DLLs for schemas $SCHEMAS to $OUTPUTALLDLL and $OUTPUTALLGRANT"
    for s in $SCHEMAS ; do 
        log "Export DLL for schema $s"
        db2look -d $DBNAME -z $s -x -e  -i $USERID -w $PASSWORD -o $TMP
        [ $? -eq 0 ] || logfail "db2look for schema failed"
        cat $TMP >>$OUTPUTALLDLL
        db2look -d $DBNAME -z $s -xd -i $USERID -w $PASSWORD -o $TMP
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
    local -r OUTPUTDB2DLL=$OUTPUTALLDIR/db2dll.sql
    rm -f $OUTPUTDB2DLL
    log "Export DB2 managed tables to $OUTPUTDB2DLL"
    local -r TMP=`mktemp`
    local -r TMP1=`mktemp`
    selectdb2tables $TMP
    while read -r line; do 
        log "Export DLL for $line"
        db2look -d $DBNAME -t $line -x -e  -i $USERID -w $PASSWORD -o $TMP1
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

printhelp() {
    echo "export.sh /action/"
    echo   "all : Export all dlls for schemas $SCHEMA"
    echo   "db2 : Export dlls for tables managed by DB2"
    echo   "db2tables: Export DB2 tables managed to DB2"
}

case $1 in
    all) exportalldll;;
    db2) exportdb2dll;;
    db2tables) exportdb2tables;;
    *) printhelp;;
esac