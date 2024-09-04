# Requires you to be on Server with admin access
$swis = Connect-Swis -Certificate

# Custom Properties Examples

$NullCityQuery = "SELECT [Nodes].caption, [Nodes].CustomProperties.Uri as [CustomPropertyURI] FROM Orion.Nodes [Nodes] where [Nodes].CustomProperties.City is NULL"
$AllNodesWithNullCity = Get-SwisData $swis $NullCityQuery

ForEach-Object ($node in $AllNodesWithNullCity ){
    $NodeCustomPropertyURI = $node.CustomPropertyURI
    $node.caption
    If ( ($node.caption).startswith('h2')) {
        $CustomPropertyCityValue = 'Dublin'
    }Else{
        $CustomPropertyCityValue = 'Columbus'
    }
    $customProps = @{
                City    = $CustomPropertyCityValue
    }
    Set-SwisObject $swis -Uri $NodeCustomPropertyURI -Properties $customProps
}

# Discovery Examples
# https://github.com/solarwinds/OrionSDK/blob/master/Samples/PowerShell/DiscoverSnmpV3Node.ps1
# This sample script shows how to use the Orion Discovery API to discover and import one node using SNMPv3 credentials.

Function DiscoverIP($ip) {
    $snmpv3credentialname1 = "Network_1"
    $snmpv3credentialname2 = "Network_2"
    $snmpv3credentialname3 = "Network_3"
    $engindId = 1
    $DeleteProfileAfterDiscoveryCompletes = "true"

    # Get the ID of the named SNMPv3 credential
    $snmpv3credentialid1 = Get-SwisData $swis "SELECT ID FROM Orion.Credential WHERE Name=@name" @{name = $snmpv3credentialname1 }
    $snmpv3credentialid2 = Get-SwisData $swis "SELECT ID FROM Orion.Credential WHERE Name=@name" @{name = $snmpv3credentialname2 }
    $snmpv3credentialid3 = Get-SwisData $swis "SELECT ID FROM Orion.Credential WHERE Name=@name" @{name = $snmpv3credentialname3 }

    $CorePluginConfigurationContext = ([xml]"<CorePluginConfigurationContext xmlns='http://schemas.solarwinds.com/2012/Orion/Core' xmlns:i='http://www.w3.org/2001/XMLSchema-instance'>
        <BulkList>
                <IpAddress>
                        <Address>$ip</Address>
                </IpAddress>
        </BulkList>
        <Credentials>
                <SharedCredentialInfo>
                        <CredentialID>$snmpv3credentialid1</CredentialID>
                        <Order>1</Order>
                </SharedCredentialInfo>
                <SharedCredentialInfo>
                        <CredentialID>$snmpv3credentialid2</CredentialID>
                        <Order>2</Order>
                </SharedCredentialInfo>
                <SharedCredentialInfo>
                        <CredentialID>$snmpv3credentialid3</CredentialID>
                        <Order>3</Order>
                </SharedCredentialInfo>
        </Credentials>
        <WmiRetriesCount>1</WmiRetriesCount>
        <WmiRetryIntervalMiliseconds>1000</WmiRetryIntervalMiliseconds>
</CorePluginConfigurationContext>
").DocumentElement

    $CorePluginConfiguration = Invoke-SwisVerb $swis Orion.Discovery CreateCorePluginConfiguration @($CorePluginConfigurationContext)

    $StartDiscoveryContext = ([xml]"
<StartDiscoveryContext xmlns='http://schemas.solarwinds.com/2012/Orion/Core' xmlns:i='http://www.w3.org/2001/XMLSchema-instance'>
        <Name>Script Discovery $([DateTime]::Now)</Name>
        <EngineId>$engindId</EngineId>
        <JobTimeoutSeconds>3600</JobTimeoutSeconds>
        <SearchTimeoutMiliseconds>2000</SearchTimeoutMiliseconds>
        <SnmpTimeoutMiliseconds>2000</SnmpTimeoutMiliseconds>
        <SnmpRetries>1</SnmpRetries>
        <RepeatIntervalMiliseconds>1500</RepeatIntervalMiliseconds>
        <SnmpPort>161</SnmpPort>
        <HopCount>0</HopCount>
        <PreferredSnmpVersion>SNMP2c</PreferredSnmpVersion>
        <DisableIcmp>false</DisableIcmp>
        <AllowDuplicateNodes>false</AllowDuplicateNodes>
        <IsAutoImport>true</IsAutoImport>
        <IsHidden>$DeleteProfileAfterDiscoveryCompletes</IsHidden>
        <PluginConfigurations>
                <PluginConfiguration>
                        <PluginConfigurationItem>$($CorePluginConfiguration.InnerXml)</PluginConfigurationItem>
                </PluginConfiguration>
        </PluginConfigurations>
</StartDiscoveryContext>
").DocumentElement

    $DiscoveryProfileID = (Invoke-SwisVerb $swis Orion.Discovery StartDiscovery @($StartDiscoveryContext)).InnerText

    Write-Host -NoNewline "Discovery profile #$DiscoveryProfileID running..."

    # Wait until the discovery completes
    do {
        Write-Host -NoNewline "."
        Start-Sleep -Seconds 1
        $Status = Get-SwisData $swis "SELECT Status FROM Orion.DiscoveryProfiles WHERE ProfileID = @profileId" @{profileId = $DiscoveryProfileID }
    } while ($Status -eq 1)

    # If $DeleteProfileAfterDiscoveryCompletes is true, then the profile will be gone at this point, but we can still get the result from Orion.DiscoveryLogs

    $Result = Get-SwisData $swis "SELECT Result, ResultDescription, ErrorMessage, BatchID FROM Orion.DiscoveryLogs WHERE ProfileID = @profileId" @{profileId = $DiscoveryProfileID }

    # Print the outcome
    switch ($Result.Result) {
        0 { "Unknown" }
        1 { "InProgress" }
        2 { "Finished" }
        3 { "Error" }
        4 { "NotScheduled" }
        5 { "Scheduled" }
        6 { "NotCompleted" }
        7 { "Canceling" }
        8 { "ReadyForImport" }
    }
    $Result.ResultDescription
    $Result.ErrorMessage

    if ($Result.Result -eq 2) {
        # if discovery completed successfully
        # Find out what objects were discovered
        $Discovered = Get-SwisData $swis "SELECT EntityType, DisplayName, NetObjectID FROM Orion.DiscoveryLogItems WHERE BatchID = @batchId" @{batchId = $Result.BatchID }
        "$($Discovered.Count) items imported."
        $Discovered
    }
}

DiscoverIP -ip $IpToDiscover


# Keep It Clean Examples


$SwisVolumeQuery = "SELECT V.Uri FROM Orion.Volumes V where V.Caption like '%cached%' or V.Caption like '%shared%' or V.Caption like '%RAM%'"
$VolumeUris = Get-SwisData $swis $SwisVolumeQuery
$VolumeUris | Remove-SwisObject $swis

$SwisInterfaceQuery = "SELECT I.Uri
FROM
    Orion.NPM.Interfaces I
where
    (I.Node.StatusDescription  like '%up%'
    or I.Node.StatusDescription  like '%warning%'
    or I.Node.StatusDescription  like '%critical%')
    and (I.FullName like '%Ras async%'
    or I.Name like '%nu0%'
    or I.Name like 'Backplane%'
    or I.Name like 'Stack%'
    or I.FullName like '%null%'
    or I.typename like 'softwareLoopback'
    or I.Name like '%Loopback%'
    or I.Name like '%unrouted%'
    or I.StatusDescription = 'Down'
    or I.StatusDescription = 'Shutdown')"

$InterfaceUris = Get-SwisData $swis $SwisInterfaceQuery
$InterfaceUris | Remove-SwisObject $swis

# Check if VM, is it running? N.VirtualMachine.PowerState
$SwisUnmanagedQuery = "SELECT N.NodeId FROM Orion.Nodes N where N.Status = 9"
$SwisUnmanagedNodeIDs = Get-SwisData $swis -Query $SwisUnmanagedQuery
If ($SwisUnmanagedNodeIDs.count -eq 1){Invoke-SwisVerb $swis Orion.Nodes Remanage @("N:$SwisUnmanagedNodeIDs")
}elseif ($SwisUnmanagedNodeIDs.count -gt 1){
    ForEach ($nodeid in $SwisUnmanagedNodeIDs){Invoke-SwisVerb $swis Orion.Nodes Remanage @("N:$nodeid") }
}


#Find and Remove volumes that are not needed
$SwisVolumeQuery = "SELECT V.Uri FROM Orion.Volumes V where V.Caption like '%cached%' or V.Caption like '%shared%' or V.Caption like '%RAM%'"
$VolumeUris = Get-SwisData $swis $SwisVolumeQuery
$VolumeUris | Remove-SwisObject $swis


# Interface removal
$SwisInterfaceQuery = "SELECT I.Uri
FROM
    Orion.NPM.Interfaces I
where
    (I.Node.StatusDescription  like '%up%'
    or I.Node.StatusDescription  like '%warning%'
    or I.Node.StatusDescription  like '%critical%')
    and (I.FullName like '%Ras async%'
    or I.Name like '%nu0%'
    or I.Name like 'Backplane%'
    or I.Name like 'Stack%'
    or I.FullName like '%null%'
    or I.typename like 'softwareLoopback'
    or I.Name like '%Loopback%'
    or I.Name like '%unrouted%'
    or I.StatusDescription = 'Down'
    or I.StatusDescription = 'Shutdown')"

$InterfaceUris = Get-SwisData $swis $SwisInterfaceQuery
$InterfaceUris | Remove-SwisObject $swis


#Re-manage Example

# Check VM, is it running? use: N.VirtualMachine.PowerState
$SwisUnmanagedQuery = "SELECT N.NodeId FROM Orion.Nodes N where N.Status = 9"
$SwisUnmanagedNodeIDs = Get-SwisData $swis -Query $SwisUnmanagedQuery
If ($SwisUnmanagedNodeIDs.count -eq 1){Invoke-SwisVerb $swis Orion.Nodes Remanage @("N:$SwisUnmanagedNodeIDs")
}elseif ($SwisUnmanagedNodeIDs.count -gt 1){
    ForEach ($nodeid in $SwisUnmanagedNodeIDs){Invoke-SwisVerb $swis Orion.Nodes Remanage @("N:$nodeid") }
}


#App Monitor on other github repo
