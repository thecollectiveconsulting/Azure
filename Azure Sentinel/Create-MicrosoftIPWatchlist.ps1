<#
.SYNOPSIS
    This script will retrieve all the current Microsoft Public IP addresses and add them in an Azure Sentinel watchlist.

.DESCRIPTION
    This script will download the current Microsoft Azure Public IP addresses through the parameter 'downloadURL'.
    It will parse the the IP-addresses found in this json file and add the IP-addresses to a Azure Sentinel watchlist.

    This scripts requires a service principal with Contributor access to the Azure Sentinel workspaces.
    
    The watchlist that will be created will have two columns 'Name' and 'IP'.
    IP is an IPv4 ranges, where Name is the name of the service that the IP belogns to.

.PARAMETER downloadURL
    URL to download Microsoft Cloud IP's from

.PARAMETER clientSecret
    ClientSecret for Service Principal with access to the Sentinel workspace

.PARAMETER clientID
    ClientID for Service Principal with access to the Sentinel workspace

.PARAMETER tenantID
    TenantID for Service Principal with access to the Sentinel workspace

.PARAMETER watchlistName
    Sentinel watchlist for the Microsoft IP's. If it doesn't exist yet, it will be created

.PARAMETER sentinelSubscriptionID
    SubscriptionID of the Sentinel workspace

.PARAMETER sentinelRG
    Resource group of the Sentinel workspace

.PARAMETER sentinelName
    Name of the Sentinel workspace
    

.NOTES
    File Name  : Create-MicrosoftIPWatchlist.ps1  
    Author     : Thijs Lecomte 
    Company    : The Collective Consulting BV
#>

#region Parameters
#Define Parameter LogPath
param (
    $downloadURL = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519",
    $clientSecret = "",
    $clientID = "",
    $tenantID = "",
    $watchlistName = "MSCloudIPs",
    $sentinelSubscriptionID = "",
    $sentinelRG = "",
    $sentinelName = ""
)
#endregion

# Create WebResponseObject from Download URL
$WebResponseObj = Invoke-WebRequest -Uri $downloadURL -UseBasicParsing

# Find all href tags and match for json string in URL
$OutputUrl = $WebResponseObj.Links  | Where-Object {$_.href -like "*.json"} | Get-Unique | % href

$RequestOutput = Invoke-RestMethod -Uri $OutputUrl 

$body=@{
    client_id=$clientid
    client_secret=$clientsecret
    resource="https://management.azure.com"
    grant_type="client_credentials"
}

try {
    $accesstoken = Invoke-WebRequest -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token" -ContentType "application/x-www-form-urlencoded" -Body $body -Method Post
}
catch {
    Write-Error 'Error retrieving access token'
    Write-Error $_.Exception.Message
}


$accessToken = $accessToken.content | ConvertFrom-Json

$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'="Bearer " + $accessToken.access_token
    'ExpiresOn'=$accessToken.expires_in
    'Content-Encoding'='gzip'
}

$watchListFound = $true
try{
    Write-Output "Check if watchlist exists"
    $WatchList = Invoke-WebRequest -Uri "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$sentinelRG/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$WatchListName`?api-version=2019-01-01-preview"  -Headers $authHeader -Method GET -ContentType 'application/json; charset=utf-8' 
}
catch{
    $watchListFound = $false
    Write-Output "$WatchListName is not found"
}

if(!$watchListFound){
    Write-Output "Creating watchlist"
$JSON = @"
{
    "properties": {
        "contentType": "text/csv",
        "description": "csv1",
        "displayName": "$WatchListName",
        "numberOfLinesToSkip": "0",
        "provider": "Microsoft",
        "rawContent": "",
        "source": "Local file"
    }
}
"@
    Invoke-RestMethod -Uri "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$sentinelRG/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$WatchListName`?api-version=2019-01-01-preview" -Body $JSON -Headers $authHeader -Method PUT -ContentType 'application/json; charset=utf-8' 
}



#Because of the size of the json document, one request will be made per Azure service
Write-Output "Adding content to WatchList"
foreach($value in $RequestOutput.Values){
    Write-Output "Adding $($value.Name)"
    $CSVContent = "Name,Ranges\r\n"

    foreach($IP in $value.properties.addressPrefixes){
        $CSVContent += "$($value.name), $($IP)\r\n"
    }
    
    
$JSON = @"
{
    "properties": {
        "contentType": "text/csv",
        "description": "csv1",
        "displayName": "$WatchListName",
        "numberOfLinesToSkip": "0",
        "provider": "Microsoft",
        "rawContent": "$CSVContent",
        "source": "Local file"
    }
}
"@
    try {
        Invoke-RestMethod -Uri "https://management.azure.com/subscriptions/$subscriptionID/resourceGroups/$sentinelRG/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$WatchListName`?api-version=2019-01-01-preview" -Body $JSON -Headers $authHeader -Method PUT -ContentType 'application/json; charset=utf-8' 
    }
    catch {
        Write-Error 'Error adding data to watchlist'
        Write-Error $_.Exception.Message
    }
}  
