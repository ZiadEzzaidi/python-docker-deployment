# Creates the server role, the firewall and the EC2 server, then waits until the app answers.
param(
    [string]$AwsProfile = "default",
    [string]$Region = "eu-north-1",
    [ValidatePattern('^\d+\.\d+$')][string]$Version = "1.0",
    [string]$AppMessage = "Deployed on AWS",
    [string]$AllowedIp = "",
    [string]$AwsCli = "aws"
)
. "$PSScriptRoot\common.ps1"

if (-not $AllowedIp) { $AllowedIp = (Invoke-RestMethod https://checkip.amazonaws.com).Trim() }

Write-Host "1/3 Server role (Systems Manager access only)"
if (-not (Test-Aws iam get-role --role-name "$Name-server")) {
    Invoke-Aws iam create-role --role-name "$Name-server" `
        --assume-role-policy-document "file://$PSScriptRoot\trust.json" `
        --tags "Key=Project,Value=$Name" | Out-Null
    Invoke-Aws iam attach-role-policy --role-name "$Name-server" `
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore | Out-Null
    Invoke-Aws iam create-instance-profile --instance-profile-name "$Name-server" `
        --tags "Key=Project,Value=$Name" | Out-Null
    Invoke-Aws iam add-role-to-instance-profile --instance-profile-name "$Name-server" `
        --role-name "$Name-server" | Out-Null
}

Write-Host "2/3 Firewall: HTTP port 80 from $AllowedIp only"
$vpc = Invoke-Aws ec2 describe-vpcs --filters Name=is-default,Values=true --query "Vpcs[0].VpcId" --output text
$sg = Invoke-Aws ec2 create-security-group --group-name "$Name-web" `
    --description "HTTP from allowed IP only" --vpc-id $vpc `
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$Name}]" `
    --query GroupId --output text
Invoke-Aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port 80 --cidr "$AllowedIp/32" | Out-Null

Write-Host "3/3 EC2 server running image version $Version"
$ami = Invoke-Aws ssm get-parameter `
    --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 `
    --query Parameter.Value --output text

# Git may check the script out with CRLF line endings, which bash cannot run.
$userData = [IO.File]::ReadAllText("$PSScriptRoot\user-data.sh") -replace "`r`n", "`n"
$userData = $userData.Replace("__VERSION__", $Version).Replace("__APP_MESSAGE__", $AppMessage)
$userDataFile = Join-Path ([IO.Path]::GetTempPath()) "$Name-user-data.sh"
[IO.File]::WriteAllText($userDataFile, $userData)

# A freshly created instance profile can take a few seconds to become usable.
for ($attempt = 1; ; $attempt++) {
    try {
        $instanceId = Invoke-Aws ec2 run-instances --image-id $ami --instance-type t3.micro --count 1 `
            --iam-instance-profile "Name=$Name-server" --security-group-ids $sg `
            --user-data "file://$userDataFile" `
            --metadata-options HttpTokens=required,HttpEndpoint=enabled `
            --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$Name-server},{Key=Project,Value=$Name}]" "ResourceType=volume,Tags=[{Key=Project,Value=$Name}]" `
            --query "Instances[0].InstanceId" --output text
        break
    } catch {
        if ($attempt -ge 6) { throw }
        Start-Sleep -Seconds 10
    }
}
Remove-Item $userDataFile

Invoke-Aws ec2 wait instance-running --instance-ids $instanceId | Out-Null
$ip = Invoke-Aws ec2 describe-instances --instance-ids $instanceId `
    --query "Reservations[0].Instances[0].PublicIpAddress" --output text
Write-Host "Server $instanceId started at $ip, waiting for the app..."
$health = Wait-Health $ip
Write-Host "Ready: http://$ip  ($($health | ConvertTo-Json -Compress))"
