#region Function Start-AzureBlobStorageTransfer
Function Start-AzureBlobStorageTransfer {
<#
.SYNOPSIS
    Starts an azure blob storage transfer.
.DESCRIPTION
    Starts an azure blob storage transfer using bits or outputs a single blob content to the pipeline.
.PARAMETER Url
    Specifies the azure containter URL.
.PARAMETER SasToken
    Specifies the azure blob/container SAS security token.
.PARAMETER Path
    Specifies the destination path for the dowloaded blobs.
.PARAMETER Force
    Overwrites the existing blob even if it has the same name and size. I can't think why this would be needed but I added it anyway.
.PARAMETER BlobContentOnly
    This switch specifies return the content of the blob to the pipeline if the azure URL points to a single blob.
.EXAMPLE
    Start-AzureBlobStorageTransfer -Url 'https://<storageaccount>.blob.core.windows.net/<Containter>' -SasToken '<AccessToken>' -Path 'D:\Temp' -Force
.EXAMPLE
    Start-AzureBlobStorageTransfer -Url 'https://<storageaccount>.blob.core.windows.net/<Container>/<Blob>' -SasToken 'SomeAccessToken' -BlobContentOnly
.INPUTS
    None.
.OUTPUTS
    System.Array.
    System.String.
.NOTES
    If the blob is already present and has the same size, Operation will return 'Skipped'.
    If the blob is already present and has the same size, but 'Force' parameter has been specified, Operation will return 'Overwritten'.
    This is an internal script function and should typically not be called directly.
    Credit to Roger Zander
.LINK
    https://rzander.azurewebsites.net/download-files-from-azure-blob-storage-with-powershell/
.LINK
    https://MEM.Zone
.LINK
    https://MEM.Zone/GIT
.LINK
    https://MEM.Zone/ISSUES
.COMPONENT
    Azure Blob Storage Rest API
.FUNCTIONALITY
    Downloads to local storage
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$true,ParameterSetName='GetBlobs',HelpMessage='Containter or Blob URL:',Position=0)]
        [Parameter(Mandatory=$true,ParameterSetName='GetContent',HelpMessage='Containter or Blob URL:',Position=0)]
        [ValidateNotNullorEmpty()]
        [Alias('Location')]
        [string]$Url,
        [Parameter(Mandatory=$true,ParameterSetName='GetBlobs',HelpMessage='Containter or Blob SAS Token:',Position=1)]
        [Parameter(Mandatory=$true,ParameterSetName='GetContent',HelpMessage='Containter or Blob SAS Token:',Position=1)]
        [ValidateNotNullorEmpty()]
        [Alias('Sas')]
        [string]$SasToken,
        [Parameter(Mandatory=$true,ParameterSetName='GetBlobs',HelpMessage='Local Download Path:',Position=2)]
        [Parameter(Mandatory=$false,ParameterSetName='GetContent',HelpMessage='Local Download Path:',Position=2)]
        [Alias('Destination')]
        [string]$Path,
        [Parameter(Mandatory=$false,ParameterSetName='GetBlobs')]
        [Alias('Overwrite')]
        [switch]$Force,
        [Parameter(Mandatory=$false,ParameterSetName='GetContent')]
        [Alias('GetContent')]
        [switch]$BlobContentOnly
    )
    Begin {

        ## Remove the '?' from the SAS string if needed
        If ($SasToken[0] -eq '?') { $SasToken = $SasToken -replace ('\?', '') }
    }
    Process {
        Try {

            ## Get azure blob list
            $AzureBlobList = Get-AzureBlobStorageItem -Url $Url -Sas $SasToken

            ## If $GetContent is specified and there is just one blob, get blob content.
            If ($PSCmdlet.ParameterSetName -eq 'GetContent') {
                #  Check if just one item is found
                If (($AzureBlobList | Measure-Object).Count -eq 1) {
                    #  Build URI
                    [string]$Uri = '{0}?{1}' -f ($Url, $SasToken)
                    #  Invoke REST API
                    $Result = Invoke-RestMethod -Uri $Uri -Method 'Get' -UseBasicParsing
                }
                Else { Throw 'Cannot get content for more than one blob at a time!' }
            }
            Else {

                ## Get local blob list
                $LocalBlobList = Get-ChildItem -Path $Path -File -ErrorAction 'SilentlyContinue' | Select-Object -Property 'Name', @{Name = 'Size(KB)'; Expression = {'{0:N2}' -f ($_.Length / 1KB)}}

                ## Create destination folder
                New-Item -Path $Path -ItemType 'Directory' -ErrorAction 'SilentlyContinue' | Out-Null

                ## Process blobs one by one
                $Result = ForEach ($Blob in $AzureBlobList) {

                    ## If the blob is already present and the same size, set the 'Skip' flag.
                    [psobject]$LocalBlobLookup = $LocalBlobList | Where-Object { $_.Name -eq $Blob.Name -and $_.'Size(KB)' -eq $Blob.'Size(KB)' } | Select-Object -Property 'Name'
                    [boolean]$SkipBlob = [boolean](-not [string]::IsNullOrEmpty($LocalBlobLookup))

                    ## Assemble Destination and URI
                    [string]$Destination = Join-Path -Path $Path -ChildPath $Blob.Name
                    [string]$Uri = '{0}?{1}' -f ($Blob.Url, $SasToken)
                    [boolean]$Overwite = $Force -and $SkipBlob

                    ## Tansfer blob using BITS
                    If (-not $SkipBlob -or $Force) { Start-BitsTransfer -Source $Uri -Destination $Destination -HttpMethod 'Get' -Description $Destination -DisplayName $Blob.Url -ErrorAction 'Stop' }

                    ## Check if last operation was successful and set error message
                    [boolean]$ShowError = If ($?) { $false; $ErrorMessage = $null } else { $true; $ErrorMessage = -join ('Error: ', $Error[0].Exception.Message) };

                    ## Build output object
                    [pscustomobject]@{
                        'Name'      = $Blob.Name
                        'Size(KB)'  = '{0:N2}' -f ($Blob.'Size(KB)')
                        'Url'       = $Blob.Url
                        'Path'      = $Path
                        'Operation' = Switch ($true) {
                            $ShowError { $ErrorMessage; break }
                            $Overwite  { 'Overwritten'; break }
                            $SkipBlob  { 'Skipped' ; break }
                            Default    { 'Downloaded' }
                        }
                    }
                }
            }
        }
        Catch {
            $PSCmdlet.ThrowTerminatingError($PSItem)
        }
        Finally {
            Write-Output -InputObject $Result
        }
    }
    End {
    }
}
#endregion