$web = get-spweb http://sharepoint-server/siteToBeCleaned

function CleanSite( $w ) 
{ 
    $ws = $w.Webs; 
    foreach( $w1 in $ws) 
    { 
        CleanSite($w1) 
    } 
    echo $w.Title 
    $w.Delete()

}

CleanSite $web