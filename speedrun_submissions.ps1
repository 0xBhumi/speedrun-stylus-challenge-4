#Requires -Version 7
$ErrorActionPreference = "Stop"

# Bypass execution policy to avoid permission issues
try {
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop | Out-Null
    Write-Host "✅ Execution policy set to Bypass for this session" -ForegroundColor Green
} catch {
    Write-Host "⚠️ Could not set execution policy. You may need to run: powershell -ExecutionPolicy Bypass -File .\submit.ps1" -ForegroundColor Yellow
}

function Say([string]$message) { Write-Host "`n$message" }

function Get-SmartInput([string]$prompt, [bool]$allowEmpty = $false) {
  do {
    Write-Host "$prompt" -NoNewline
    $input = ""
    $startTime = Get-Date
    
    # Read input character by character to detect paste
    while ($true) {
      $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
      
      if ($key.VirtualKeyCode -eq 13) { # Enter key
        break
      } elseif ($key.VirtualKeyCode -eq 8) { # Backspace
        if ($input.Length -gt 0) {
          $input = $input.Substring(0, $input.Length - 1)
          Write-Host "`b `b" -NoNewline
        }
      } elseif ($key.Character -and $key.Character -match '[^\x00-\x1F]') { # Printable character
        $input += $key.Character
        Write-Host $key.Character -NoNewline
        
        # Check if this looks like a paste (multiple chars in short time)
        $currentTime = Get-Date
        if (($currentTime - $startTime).TotalMilliseconds -lt 100 -and $input.Length -gt 10) {
          # Likely a paste, auto-process after brief delay
          Start-Sleep -Milliseconds 200
          break
        }
      }
    }
    
    Write-Host "" # New line
    
    if (-not $allowEmpty -and [string]::IsNullOrWhiteSpace($input)) {
      Write-Host "❌ Input cannot be empty. Please try again." -ForegroundColor Red
    }
  } while (-not $allowEmpty -and [string]::IsNullOrWhiteSpace($input))
  
  return $input.Trim()
}

function Get-PlainTextFromSecureString([System.Security.SecureString]$secure) {
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { 
    return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) 
  } finally { 
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) 
  }
}



function Ensure-Git() {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "❌ git not found. Please install Git and try again."; exit 1
  }
}

function Check-GitConfig() {
  # Check if global git config is already set
  $globalUserName = git config --global user.name 2>$null
  $globalUserEmail = git config --global user.email 2>$null
  
  $gitUserName = ""
  $gitUserEmail = ""
  
  if ($globalUserName -and $globalUserEmail) {
    Write-Host "✅ Found existing global git configuration:" -ForegroundColor Green
    Write-Host "   user.name:  $globalUserName" -ForegroundColor Green
    Write-Host "   user.email: $globalUserEmail" -ForegroundColor Green
    do {
      $useExisting = Read-Host "Use existing git configuration? (Y/N)"
      if ($useExisting -match '^[YyNn]$') { break }
      Write-Host "❌ Please enter Y or N." -ForegroundColor Red
    } while ($true)
    if ($useExisting -eq "Y" -or $useExisting -eq "y") {
      $gitUserName = $globalUserName
      $gitUserEmail = $globalUserEmail
    }
  }
  
  if (-not $gitUserName -or -not $gitUserEmail) {
    $gitUserName = Read-Host "Enter your git user.name (e.g., yourusername)"
    $gitUserEmail = Read-Host "Enter your git user.email (e.g., you@example.com)"
    if (-not $gitUserName) { Write-Host "❌ user.name cannot be empty."; exit 1 }
    if (-not $gitUserEmail) { Write-Host "❌ user.email cannot be empty."; exit 1 }
  }
  
  return @{"Name" = $gitUserName; "Email" = $gitUserEmail}
}

# ---------------- Container Config ----------------
$IMG  = "abxglia/speedrun-stylus:0.1"
$NAME = "speedrun-stylus"
$PORT = 3000

function Ensure-Docker() {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Docker not found. Install Docker Desktop."; exit 1
  }
  try { docker info | Out-Null } catch { Write-Host "❌ Docker daemon not running. Start Docker Desktop."; exit 1 }
  
  # Check if the image is already pulled
  $imageExists = docker images -q $IMG 2>$null
  if ($imageExists) {
    Write-Host "✅ Docker image '$IMG' already pulled" -ForegroundColor Green
  } else {
    Say "📦 Pulling Docker image '$IMG'..."
    docker pull $IMG | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-Host "✅ Docker image pulled successfully" -ForegroundColor Green
    } else {
      Write-Host "❌ Failed to pull Docker image" -ForegroundColor Red
      exit 1
    }
  }
}

function Ensure-Container() {
  $inspect = docker inspect -f '{{.State.Status}}' $NAME 2>$null
  if ($LASTEXITCODE -eq 0 -and $inspect -and $inspect.Trim()) {
    $status = $inspect.Trim()
    if ($status -eq 'running') {
      Say "♻️ Container '$NAME' already running; reusing."
    } else {
      Say "▶️ Starting existing container '$NAME'..."
      docker start $NAME | Out-Null
    }
  } else {
    Say "🚀 Starting container..."
    docker run -d --name $NAME `
      -v ${PWD}:/app `
      -v speedrun-yarn-cache:/root/.cache/yarn `
      -v speedrun-cargo-registry:/root/.cargo/registry `
      -v speedrun-cargo-git:/root/.cargo/git `
      -v speedrun-rustup:/root/.rustup `
      -v speedrun-foundry:/root/.foundry `
      -p "$PORT`:3000" `
      $IMG tail -f /dev/null | Out-Null
  }
}

function Select-ChallengeBranch() {
  while ($true) {
    Write-Host "Choose a challenge (for branch selection):
1) counter
2) nft
3) vending-machine
4) multi-sig
5) stylus-uniswap"
    $choice = Read-Host "Enter 1-5"
    switch ($choice) {
      "1" { return "counter" }
      "2" { return "nft" }
      "3" { return "vending-machine" }
      "4" { return "multi-sig" }
      "5" { return "stylus-uniswap" }
      default { Write-Host "❌ Invalid choice. Please enter a number between 1 and 5." -ForegroundColor Red }
    }
  }
}

function Find-RepoPath([string]$branch) {
  # Look for directories with .git first (existing repos)
  $candidates = @(
    "/app",
    "/app/speedrun-$branch", 
    "/app/test-vending"
  )
  
  foreach ($candidate in $candidates) {
    $hasGit = docker exec $NAME test -d "$candidate/.git" 2>$null
    if ($LASTEXITCODE -eq 0) {
      return $candidate
    }
  }
  
  # Fallback: find any .git directory
  $result = docker exec $NAME find /app -maxdepth 2 -name ".git" -type d 2>$null | Select-Object -First 1
  if ($result -and $result.Trim()) {
    return ($result.Trim() -replace "/.git$", "")
  }
  
  # If no .git found, look for project directories (packages/ folder or package.json)
  foreach ($candidate in $candidates) {
    $hasPackages = docker exec $NAME test -d "$candidate/packages" 2>$null
    $hasPackageJson = docker exec $NAME test -f "$candidate/package.json" 2>$null
    if ($LASTEXITCODE -eq 0 -or $hasPackageJson -eq 0) {
      return $candidate
    }
  }
  
  # Final fallback: find any directory with packages folder
  $result = docker exec $NAME find /app -maxdepth 2 -name "packages" -type d 2>$null | Select-Object -First 1
  if ($result -and $result.Trim()) {
    return ($result.Trim() -replace "/packages$", "")
  }
  
  return $null
}

function Find-PackagesFolder([string]$repoPath) {
  # Find directory containing packages folder
  $packagesPath = docker exec $NAME bash -c "find '$repoPath' -name 'packages' -type d | head -1" 2>$null
  if ($packagesPath -and $packagesPath.Trim()) {
    $packagesPath = ($packagesPath -replace "`r", "").Trim()
    $parentDir = docker exec $NAME bash -c "dirname '$packagesPath'" 2>$null
    if ($parentDir -and $parentDir.Trim()) {
      return ($parentDir -replace "`r", "").Trim()
    }
  }
  return $repoPath
}

function Ensure-Remote([string]$remoteUrl, [string]$repoPath) {
  # Simple: always set the remote (overwrites if exists)
  docker exec $NAME bash -c "cd '$repoPath' && git remote remove origin 2>/dev/null || true" | Out-Null
  docker exec $NAME bash -c "cd '$repoPath' && git remote add origin '$remoteUrl'" | Out-Null
}

function Ensure-Branch([string]$branch, [string]$repoPath) {
  # Simple: rename current branch to desired branch
  docker exec $NAME bash -c "cd '$repoPath' && git branch -M '$branch'" | Out-Null
}

function Commit-If-Needed([string]$message, [string]$repoPath) {
  # Simple: add all and commit with --no-verify to skip hooks/lint-staged
  docker exec $NAME bash -c "cd '$repoPath' && git add . && git commit --no-verify -m '$message' || true" | Out-Null
}

# ---------------- Main ----------------
Ensure-Git
Ensure-Docker
Ensure-Container

# 1) Inputs
do {
  $origin = Read-Host "Enter your GitHub repository origin URL (e.g., https://github.com/username/repo.git)"
  if ($origin -match '^https://github.com/[^/]+/[^/]+(\.git)?$') { break }
  Write-Host "❌ Invalid repository URL. Please enter a GitHub https URL like: https://github.com/owner/repo.git" -ForegroundColor Red
} while ($true)

# Check git configuration
$gitConfig = Check-GitConfig
$gitUserName = $gitConfig.Name
$gitUserEmail = $gitConfig.Email

# Collect private key for later use in smart cache and deployment
Say "🔐 Enter your wallet private key for smart cache and deployment operations"
do {
  $securePrivateKey = Read-Host -AsSecureString "Private Key (will not be displayed)"
  $userPrivateKey = Get-PlainTextFromSecureString $securePrivateKey
  $userPrivateKey = ($userPrivateKey -replace "`r", "").Trim()
  $pkNoPrefix = ($userPrivateKey -replace '^0x','')
  if ($pkNoPrefix -match '^[0-9a-fA-F]{64}$') {
    $userPrivateKey = '0x' + $pkNoPrefix
    break
  }
  Write-Host "❌ Invalid private key. Provide a 64-hex-character key (with or without 0x)." -ForegroundColor Red
} while ($true)

$branch = Select-ChallengeBranch

# 2) Find the repository path inside container
$repoPath = Find-RepoPath -branch $branch
if (-not $repoPath) {
  Write-Host "❌ No speedrun project found inside container. Looking for a directory with:"
  Write-Host "   - .git folder (existing git repository)"
  Write-Host "   - packages/ folder (speedrun project structure)"
  Write-Host "   - package.json file (Node.js project)"
  Write-Host ""
  Write-Host "💡 Make sure you have:"
  Write-Host "   1. Cloned a speedrun project properly, OR"
  Write-Host "   2. Created a project directory with packages/ folder or package.json"
  Write-Host "   3. If .git folder was deleted, the script will initialize a fresh repository"
  exit 1
}
# Sanitize Windows line endings to avoid bash errors
if ($repoPath) {
  $repoPath = ($repoPath -replace "`r", "").Trim()
}
Say "📁 Using speedrun project: $repoPath"

# 3) Configure git identity inside container
Say "👤 Setting git identity inside container..."
docker exec $NAME bash -c "cd '$repoPath' && git config user.name '$gitUserName'" | Out-Null
docker exec $NAME bash -c "cd '$repoPath' && git config user.email '$gitUserEmail'" | Out-Null

$confirmNameResult = docker exec $NAME bash -c "cd '$repoPath' && git config user.name" 2>$null
$confirmEmailResult = docker exec $NAME bash -c "cd '$repoPath' && git config user.email" 2>$null
$confirmName = if ($confirmNameResult) { $confirmNameResult.Trim() } else { "(not set)" }
$confirmEmail = if ($confirmEmailResult) { $confirmEmailResult.Trim() } else { "(not set)" }
Write-Host "   user.name:  $confirmName"
Write-Host "   user.email: $confirmEmail"

# 4) Set remote origin inside container (for reference only)
Say "🔗 Setting remote origin: $origin"
Ensure-Remote -remoteUrl $origin -repoPath $repoPath
Say "✅ Remote origin set in container (git operations will be done from fresh terminal)"

# 5) Ensure correct branch inside container
Ensure-Branch -branch $branch -repoPath $repoPath

# 6) Get commit message from user and commit if needed
Say "💡 IMPORTANT: You will handle your own commits in the fresh terminal that opens next."
Say "   The script will NOT auto-commit with generic messages like 'Initial commit from automation script'."
Say "   You will have full control over your commit messages and git workflow."

$commitMessage = Get-SmartInput "Enter your commit message (or press Enter to skip commit): " -allowEmpty $true
if ($commitMessage) {
  Say "✅ Your commit message saved: '$commitMessage'"
  Say "💡 You'll use this message when you commit in the fresh terminal"
} else {
  Say "⏭️ No commit message provided - you can enter one in the fresh terminal"
}

# 7) Push from fresh PowerShell terminal
# Find the packages folder to determine the correct directory
$packagesDir = Find-PackagesFolder -repoPath $repoPath
Say "🚀 Opening new PowerShell terminal for git push..."
$pushScript = @"
# Change to the project directory
cd '$((Get-Location).Path)'

# Find directory containing packages folder
`$packagesPath = Get-ChildItem -Recurse -Directory -Name "packages" -ErrorAction SilentlyContinue | Select-Object -First 1
if (`$packagesPath) {
    `$projectDir = Split-Path `$packagesPath -Parent
    if (`$projectDir -and (Test-Path `$projectDir)) {
        cd `$projectDir
        Write-Host "Navigated to project directory containing packages: `$projectDir" -ForegroundColor Green
    }
} else {
    # Fallback to speedrun-$branch directory
    if (Test-Path 'speedrun-$branch') {
        cd 'speedrun-$branch'
        Write-Host "Using speedrun project directory: speedrun-$branch" -ForegroundColor Yellow
    }
}

# Initialize git repository if it doesn't exist
if (-not (Test-Path '.git')) {
    Write-Host 'Initializing new git repository...' -ForegroundColor Yellow
    git init
}

# Set git user identity
git config user.name '$gitUserName'
git config user.email '$gitUserEmail'

# Add remote origin
git remote remove origin 2>`$null
git remote add origin '$origin'

# Ensure correct branch
git branch -M '$branch'

# Check if this is a fresh repository (no commits)
`$hasCommits = git log --oneline -1 2>`$null
`$isFreshRepo = (`$LASTEXITCODE -ne 0)

# Check if there are changes to commit
`$status = git status --porcelain
if (`$status -or `$isFreshRepo) {
    if (`$isFreshRepo) {
        Write-Host 'Fresh repository detected. Adding all files for initial commit...' -ForegroundColor Yellow
    } else {
        Write-Host 'Changes detected. Auto-committing with your saved message...' -ForegroundColor Yellow
    }
    
    git add .
    
    if ('$commitMessage') {
        git commit -m '$commitMessage'
        Write-Host 'Committed with message: $commitMessage' -ForegroundColor Green
    } else {
        if (`$isFreshRepo) {
            git commit -m 'Initial commit from speedrun automation script'
            Write-Host 'Initial commit created with default message' -ForegroundColor Green
        } else {
            git commit -m 'Automated commit from speedrun script'
            Write-Host 'Committed with default message' -ForegroundColor Green
        }
    }
} else {
    Write-Host 'No changes detected. Ready to push...' -ForegroundColor Green
}

# Push to GitHub
Write-Host 'Pushing to GitHub...' -ForegroundColor Green
git push -u origin '$branch'

if (`$LASTEXITCODE -eq 0) {
    Write-Host '✅ Push successful!' -ForegroundColor Green
} else {
    Write-Host '❌ Push failed. Check your git credentials and try again.' -ForegroundColor Red
}

Write-Host 'Press Enter to close this terminal...' -ForegroundColor Yellow
[void](Read-Host)
"@

# Save the push script to a temporary file
$pushScriptPath = Join-Path $env:TEMP "push_to_github.ps1"
$pushScript | Out-File -FilePath $pushScriptPath -Encoding UTF8

# Open new PowerShell terminal with the push script
Start-Process "powershell.exe" -ArgumentList "-ExecutionPolicy", "Bypass", "-File", "`"$pushScriptPath`"" -WindowStyle Normal

Say "✅ New PowerShell terminal opened for git push"
Say "💡 Complete the push in the new terminal, then return here to continue"
Say "⏸️  Press Enter when you're ready to continue..."
Read-Host

# 2) Stylus Smart Contract Verification (Optional)
Say "🔍 Stylus Smart Contract Verification"
$verifyContract = Read-Host "Do you want to verify your Stylus smart contract? (Y/N)"
if ($verifyContract -eq "Y" -or $verifyContract -eq "y") {
  Say "🔧 Setting up contract verification..."
  
  # Find Rust project directory
  Say "📁 Locating Rust project directory..."
  $rustProjectDir = $null
  
  # Look for Cargo.lock first, then Cargo.toml, then rust-toolchain.toml
  $cargoLockDir = docker exec $NAME bash -c "find '$repoPath' -name 'Cargo.lock' -type f | head -1 | xargs dirname" 2>$null
  if ($cargoLockDir -and $cargoLockDir.Trim()) {
    $rustProjectDir = ($cargoLockDir -replace "`r", "").Trim()
  } else {
    $cargoTomlDir = docker exec $NAME bash -c "find '$repoPath' -name 'Cargo.toml' -type f | head -1 | xargs dirname" 2>$null
    if ($cargoTomlDir -and $cargoTomlDir.Trim()) {
      $rustProjectDir = ($cargoTomlDir -replace "`r", "").Trim()
    } else {
      $rustToolchainDir = docker exec $NAME bash -c "find '$repoPath' -name 'rust-toolchain.toml' -type f | head -1 | xargs dirname" 2>$null
      if ($rustToolchainDir -and $rustToolchainDir.Trim()) {
        $rustProjectDir = ($rustToolchainDir -replace "`r", "").Trim()
      }
    }
  }
  
  if (-not $rustProjectDir) {
    Write-Host "❌ Could not find Rust project directory (no Cargo.lock, Cargo.toml, or rust-toolchain.toml found)" -ForegroundColor Red
    Say "⏭️ Skipping contract verification"
  } else {
    Say "✅ Found Rust project at: $rustProjectDir"
    
    # Initialize git repository in the Rust project directory
    Say "🔧 Initializing git repository in Rust project directory..."
    docker exec $NAME bash -c "cd '$rustProjectDir' && git init" | Out-Null
    
    # Configure git identity in the Rust project
    docker exec $NAME bash -c "cd '$rustProjectDir' && git config user.name '$gitUserName'" | Out-Null
    docker exec $NAME bash -c "cd '$rustProjectDir' && git config user.email '$gitUserEmail'" | Out-Null
    
    # Add remote origin
    docker exec $NAME bash -c "cd '$rustProjectDir' && git remote add origin '$origin'" | Out-Null
    
    # Add all files and commit
    docker exec $NAME bash -c "cd '$rustProjectDir' && git add ." | Out-Null
    docker exec $NAME bash -c "cd '$rustProjectDir' && git commit -m 'Stylus smart contract verification'" | Out-Null
    
    # Create and switch to verify branch
    docker exec $NAME bash -c "cd '$rustProjectDir' && git branch -M verify" | Out-Null
    
    Say "🚀 Opening new PowerShell terminal for contract verification push..."
    $verifyPushScript = @"
# Change to the project directory
cd '$((Get-Location).Path)'

# Navigate to the Rust project directory
`$rustProjectPath = '$rustProjectDir' -replace '^/app/', ''
if (Test-Path `$rustProjectPath) {
    cd `$rustProjectPath
    Write-Host "Navigated to Rust project directory: `$rustProjectPath" -ForegroundColor Green
} else {
    Write-Host "❌ Could not find Rust project directory: `$rustProjectPath" -ForegroundColor Red
    Write-Host "Press Enter to close this terminal..." -ForegroundColor Yellow
    [void](Read-Host)
    exit 1
}

# Initialize git repository if it doesn't exist
if (-not (Test-Path '.git')) {
    Write-Host 'Initializing new git repository...' -ForegroundColor Yellow
    git init
}

# Set git user identity
git config user.name '$gitUserName'
git config user.email '$gitUserEmail'

# Add remote origin
git remote remove origin 2>`$null
git remote add origin '$origin'

# Add all files and commit
git add .
git commit -m 'Stylus smart contract verification'

# Create and switch to verify branch
git branch -M verify

# Push to verify branch
Write-Host 'Pushing to verify branch for contract verification...' -ForegroundColor Green
git push -u origin verify

if (`$LASTEXITCODE -eq 0) {
    Write-Host '✅ Contract verification push successful!' -ForegroundColor Green
    Write-Host '🎯 Your Rust contract has been pushed to the verify branch' -ForegroundColor Green
} else {
    Write-Host '❌ Push failed. Check your git credentials and try again.' -ForegroundColor Red
}

Write-Host 'Press Enter to close this terminal...' -ForegroundColor Yellow
[void](Read-Host)
"@

    # Save the verify push script to a temporary file
    $verifyPushScriptPath = Join-Path $env:TEMP "push_verify.ps1"
    $verifyPushScript | Out-File -FilePath $verifyPushScriptPath -Encoding UTF8

    # Open new PowerShell terminal with the verify push script
    Start-Process "powershell.exe" -ArgumentList "-ExecutionPolicy", "Bypass", "-File", "`"$verifyPushScriptPath`"" -WindowStyle Normal

    Say "✅ New PowerShell terminal opened for contract verification push"
    Say "💡 Complete the push in the new terminal, then return here to continue"
    Say "⏸️  Press Enter when you're ready to continue..."
    Read-Host
    
    # Clean up the .git directory in the Rust project
    Say "🧹 Cleaning up git repository in Rust project directory..."
    docker exec $NAME bash -c "cd '$rustProjectDir' && rm -rf .git" | Out-Null
    Say "✅ Git repository cleaned up from Rust project directory"
  }
} else {
  Say "⏭️ Skipping contract verification. Continuing with Smart Cache configuration..."
}

# 3) Smart Cache Configuration (Optional)
Say "🧠 Smart Cache Configuration for Gas Optimization"
$configureSmartCache = Read-Host "Are you ready for smart cache configuration for making this contract efficient for gas savings? (Y/N)"
if ($configureSmartCache -eq "Y" -or $configureSmartCache -eq "y") {
  Say "🔧 Setting up Smart Cache for gas optimization..."
  
  # Check if smart-cache-cli is already installed
  Say "🔍 Checking if smart-cache-cli is already installed..."
  docker exec $NAME bash -c "smart-cache --help" > $null 2>&1
  if ($LASTEXITCODE -eq 0) {
    Say "✅ Smart-cache-cli is already installed, skipping installation"
  } else {
    # Install smart-cache-cli globally
    Say "📦 Installing smart-cache-cli..."
    $installResult = docker exec $NAME bash -c "npm install -g smart-cache-cli" 2>&1
    if ($LASTEXITCODE -ne 0) {
      Say "⚠️ Global installation failed. Trying local installation..."
      docker exec $NAME bash -c "cd '$repoPath' && npm install smart-cache-cli" | Out-Null
      if ($LASTEXITCODE -eq 0) {
        Say "✅ Smart-cache-cli installed locally in project"
      } else {
        Write-Host "❌ Failed to install smart-cache-cli. You may need to install it manually." -ForegroundColor Red
        Write-Host "   Run: docker exec -it $NAME bash -c 'npm install -g smart-cache-cli'" -ForegroundColor Yellow
      }
    } else {
      Say "✅ Smart-cache-cli installed globally"
    }
  }
  
  # Run smart-cache init
  Say "🚀 Initializing smart cache configuration..."
  docker exec $NAME bash -c "cd '$repoPath' && npx smart-cache init" | Out-Null
  
  # Get user inputs for smart cache configuration
  $deployerAddress = Get-SmartInput "Enter your wallet address that deployed the contracts: "
  $contractAddress = Get-SmartInput "Enter your contract address (or press Enter to skip): " -allowEmpty $true
  
  # Update smartcache.toml with user values (robust approach)
  Say "🔧 Updating smartcache.toml with your addresses..."
  
  # Read current TOML, update values, write back
  $updateScript = @"
#!/bin/bash
set -e
cd '$repoPath'
f=smartcache.toml

# Ensure file exists
touch `$f

# Update deployed_by
if grep -q '^deployed_by' `$f; then
  sed -i "s/^deployed_by.*/deployed_by = \"`$1\"/" `$f
else
  echo "deployed_by = \"`$1\"" >> `$f
fi

# Update contract_address if provided
if [ -n "`$2" ]; then
  if grep -q '^contract_address' `$f; then
    sed -i "s/^contract_address.*/contract_address = \"`$2\"/" `$f
  else
    echo "contract_address = \"`$2\"" >> `$f
  fi
fi
"@

  # Write script to container and execute
  $scriptB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($updateScript))
  docker exec $NAME bash -c "echo '$scriptB64' | base64 -d > /tmp/update_toml.sh && sed -i 's/\r$//' /tmp/update_toml.sh && chmod +x /tmp/update_toml.sh"
  docker exec $NAME bash -c "/tmp/update_toml.sh '$deployerAddress' '$contractAddress'"
  Start-Sleep -Milliseconds 500
  
  Say "✅ Smart cache configuration created at: $repoPath/smartcache.toml"
  
  # Smart cache configuration retry loop
  $maxRetries = 3
  $retryCount = 0
  $smartCacheAddSuccess = $false
  
  do {
    $retryCount++
    if ($retryCount -gt 1) {
      Say "🔄 Retry attempt $retryCount of $maxRetries"
    }
    
    # Run smart-cache add command
    Say "🚀 Running smart-cache add command..."
    $addCmd = "cd '$repoPath' && npx -y smart-cache add"
    if ($contractAddress) { $addCmd = "cd '$repoPath' && npx -y smart-cache add $contractAddress" }
    $smartCacheAddOutput = docker exec $NAME bash -c $addCmd 2>&1
    $smartCacheAddSuccess = ($LASTEXITCODE -eq 0)
    
    # Display the output to user
    Write-Host "📋 Smart-cache add command output:" -ForegroundColor Cyan
    Write-Host $smartCacheAddOutput
    
    if ($smartCacheAddSuccess) {
      Say "✅ Smart-cache add command executed successfully!"
      break
    } else {
      Say "⚠️ Smart-cache add command encountered errors"
      Write-Host "Error code: $LASTEXITCODE" -ForegroundColor Yellow
      
      if ($retryCount -lt $maxRetries) {
        $retry = Read-Host "Would you like to retry with new contract address and deployer address? (Y/N)"
        if ($retry -eq "Y" -or $retry -eq "y") {
          # Get new user inputs for smart cache configuration
          $deployerAddress = Get-SmartInput "Enter your wallet address that deployed the contracts: "
          $contractAddress = Get-SmartInput "Enter your contract address (or press Enter to skip): " -allowEmpty $true
          
                     # Update smartcache.toml with new inputs
           Say "🔧 Updating smartcache.toml with new addresses..."
           docker exec $NAME bash -c "/tmp/update_toml.sh '$deployerAddress' '$contractAddress'"
          
          Say "✅ Smart cache configuration updated with new addresses"
        } else {
          break
        }
      } else {
        Say "⚠️ Maximum retry attempts reached ($maxRetries)"
        break
      }
    }
  } while ($retryCount -lt $maxRetries -and -not $smartCacheAddSuccess)
  
  # Commit and push smart cache configuration
  $smartCacheCommitMsg = Get-SmartInput "Enter commit message for smart cache configuration (or press Enter to skip): " -allowEmpty $true
  if ($smartCacheCommitMsg) {
    docker exec $NAME bash -c "cd '$repoPath' && git add smartcache.toml && git commit --no-verify -m '$smartCacheCommitMsg'" | Out-Null
    Say "✅ Smart cache configuration committed"
    
    # Check if smart-cache add was successful before pushing
    if (-not $smartCacheAddSuccess) {
      Say "⚠️ Smart-cache add command had errors after $retryCount attempts"
      $continuePush = Read-Host "Are you sure to push the code to GitHub without successful run of smart-cache add command? (Y/N)"
      if ($continuePush -ne "Y" -and $continuePush -ne "y") {
        Say "⏭️ Skipping smart cache push due to smart-cache add errors."
        $continueToRustCrate = Read-Host "Would you like to continue with Rust Crate automation? (Y/N)"
        if ($continueToRustCrate -ne "Y" -and $continueToRustCrate -ne "y") {
          Say "⏭️ Script completed. Smart cache is configured but not pushed due to errors."
          exit 0
        }
        Say "⏭️ Continuing with Rust Crate automation..."
      }
    }
    
    # Push the new changes
    Say "🚀 Opening new PowerShell terminal for smart cache push..."
    $smartCachePushScript = @"
# Change to the project directory
cd '$((Get-Location).Path)'

# Find directory containing packages folder
`$packagesPath = Get-ChildItem -Recurse -Directory -Name "packages" -ErrorAction SilentlyContinue | Select-Object -First 1
if (`$packagesPath) {
    `$projectDir = Split-Path `$packagesPath -Parent
    if (`$projectDir -and (Test-Path `$projectDir)) {
        cd `$projectDir
        Write-Host "Navigated to project directory containing packages: `$projectDir" -ForegroundColor Green
    }
} else {
    # Fallback to speedrun-$branch directory
    if (Test-Path 'speedrun-$branch') {
        cd 'speedrun-$branch'
        Write-Host "Using speedrun project directory: speedrun-$branch" -ForegroundColor Yellow
    }
}

# Initialize git repository if it doesn't exist
if (-not (Test-Path '.git')) {
    Write-Host 'Initializing new git repository...' -ForegroundColor Yellow
    git init
}

# Set git user identity
git config user.name '$gitUserName'
git config user.email '$gitUserEmail'

# Add remote origin
git remote remove origin 2>`$null
git remote add origin '$origin'

# Ensure correct branch
git branch -M '$branch'

# Check if there are changes to commit
`$status = git status --porcelain
if (`$status) {
    Write-Host 'Changes detected. Auto-committing smart cache configuration...' -ForegroundColor Yellow
    git add .
    git commit -m 'Smart cache configuration update'
    Write-Host 'Committed smart cache changes' -ForegroundColor Green
} else {
    Write-Host 'No changes detected. Ready to push...' -ForegroundColor Green
}

# Push smart cache configuration to GitHub
Write-Host 'Pushing smart cache configuration to GitHub...' -ForegroundColor Green
git push origin '$branch'

if (`$LASTEXITCODE -eq 0) {
    Write-Host '✅ Smart cache configuration pushed successfully!' -ForegroundColor Green
} else {
    Write-Host '❌ Push failed. Check your git credentials and try again.' -ForegroundColor Red
}

Write-Host 'Press Enter to close this terminal...' -ForegroundColor Yellow
[void](Read-Host)
"@

    # Save the push script to a temporary file
    $smartCachePushScriptPath = Join-Path $env:TEMP "push_smartcache.ps1"
    $smartCachePushScript | Out-File -FilePath $smartCachePushScriptPath -Encoding UTF8

    # Open new PowerShell terminal with the push script
    Start-Process "powershell.exe" -ArgumentList "-ExecutionPolicy", "Bypass", "-File", "`"$smartCachePushScriptPath`"" -WindowStyle Normal

    Say "✅ New PowerShell terminal opened for smart cache push"
    Say "💡 Complete the push in the new terminal, then return here to continue"
    Say "⏸️  Press Enter when you're ready to continue with Rust Crate automation..."
    Read-Host
  } else {
    Say "⏭️ Smart cache configuration created but not committed. You can commit manually later."
  }
} else {
  Say "⏭️ Skipping smart cache configuration. You can configure it manually later if needed."
}

# 4) Rust Crate Automation (Optional)
Say "🦀 Rust Crate Automation for Contract Optimization"
$configureRustCrate = Read-Host "Are you ready to use RUST crate to automate the process? (Y/N)"
if ($configureRustCrate -eq "Y" -or $configureRustCrate -eq "y") {
  Say "🔧 Setting up Rust crate automation..."
  
  # Find Cargo.toml directory
  Say "📁 Locating Cargo.toml directory..."
  $cargoDir = docker exec $NAME bash -c "find '$repoPath' -name 'Cargo.toml' -type f | head -1 | xargs dirname" 2>$null
  if (-not $cargoDir -or -not $cargoDir.Trim()) {
    $cargoDir = docker exec $NAME bash -c "find '$repoPath' -name 'rust-toolchain.toml' -type f | head -1 | xargs dirname" 2>$null
  }
  
  if (-not $cargoDir -or -not $cargoDir.Trim()) {
    Write-Host "❌ Could not find Cargo.toml or rust-toolchain.toml directory" -ForegroundColor Red
    Say "⏭️ Skipping Rust crate automation"
  } else {
    $cargoDir = ($cargoDir -replace "`r", "").Trim()
    Say "✅ Found Rust project at: $cargoDir"
    
    # Install stylus-cache-sdk
    Say "📦 Installing stylus-cache-sdk..."
    docker exec $NAME bash -c "cd '$cargoDir' && cargo add stylus-cache-sdk" | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Say "✅ stylus-cache-sdk installed successfully"
    } else {
      Write-Host "❌ Failed to install stylus-cache-sdk" -ForegroundColor Red
      Say "⏭️ Skipping Rust crate automation"
      return
    }
    
    # Find and update lib.rs
    Say "🔧 Updating lib.rs file..."
    $libRsPath = docker exec $NAME bash -c "find '$cargoDir' -name 'lib.rs' -type f | head -1" 2>$null
    if (-not $libRsPath -or -not $libRsPath.Trim()) {
      Write-Host "❌ Could not find lib.rs file" -ForegroundColor Red
      Say "⏭️ Skipping lib.rs updates"
    } else {
      $libRsPath = ($libRsPath -replace "`r", "").Trim()
      Say "✅ Found lib.rs at: $libRsPath"
      
      # Update lib.rs with import and cacheable function
  $updateLibScript = @"
#!/bin/bash
set -e
libfile='$libRsPath'

  # Add import if not already present
if ! grep -q "use stylus_cache_sdk" "`$libfile"; then
  # Add after extern crate alloc line
  sed -i '/extern crate alloc;/a use stylus_cache_sdk::{is_contract_cacheable};' "`$libfile"
fi

# Add is_cacheable function if not already present
if ! grep -q "pub fn is_cacheable" "`$libfile"; then
  # Find impl block and add the function
  if grep -q "impl " "`$libfile"; then
    # Add the function before the last closing brace of the impl block
    sed -i '/impl /,/^}/ {
      /^}/ i\    pub fn is_cacheable(&self) -> bool {\
        is_contract_cacheable()\
    }\

    }' "`$libfile"
  fi
fi
"@
      
      $libScriptB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($updateLibScript))
      docker exec $NAME bash -c "echo '$libScriptB64' | base64 -d > /tmp/update_lib.sh && sed -i 's/\r$//' /tmp/update_lib.sh && chmod +x /tmp/update_lib.sh"
      docker exec $NAME bash -c "/tmp/update_lib.sh '$libRsPath'"
      
      Say "✅ lib.rs updated with stylus-cache-sdk integration"
      
      # Ask user to make contract unique
      Say "🎯 Make Your Contract Unique"
      Write-Host "To make your contract unique, you should rename one of your functions."
      Write-Host "For example: 'set_number' → 'set_number_yourname'"
      Write-Host ""
      $makeUnique = Read-Host "Would you like to make manual changes to make your contract unique? (Y/N)"
      if ($makeUnique -eq "Y" -or $makeUnique -eq "y") {
        Write-Host "✅ Please manually edit your lib.rs file to rename a function and make it unique."
        Write-Host "📝 The file is located at: $libRsPath"
        Write-Host "⏸️  Press Enter when you're done making changes..."
        Read-Host
      }
      
      # Ensure WebAssembly target is installed
      Say "🔧 Ensuring WebAssembly target is installed..."
      docker exec $NAME bash -c "rustup target add wasm32-unknown-unknown" | Out-Null
      if ($LASTEXITCODE -eq 0) {
        Say "✅ WebAssembly target ready"
      } else {
        Write-Host "⚠️ Warning: Could not install wasm32-unknown-unknown target" -ForegroundColor Yellow
      }
      
      # Deploy contract with cargo stylus
      Say "🚀 Deploying contract with cargo stylus..."
      Write-Host "Running: cargo stylus deploy --endpoint='https://sepolia-rollup.arbitrum.io/rpc' --private-key=<your-key> --no-verify"
      
      # Use the private key collected at the beginning of the script
      $deployOutput = docker exec $NAME bash -c "cd '$cargoDir' && cargo stylus deploy --endpoint='https://sepolia-rollup.arbitrum.io/rpc' --private-key='$userPrivateKey' --no-verify" 2>&1
      $deploySuccess = ($LASTEXITCODE -eq 0)
      
      # Display deploy output
      Write-Host "📋 Cargo stylus deploy output:" -ForegroundColor Cyan
      Write-Host $deployOutput
      
      if ($deploySuccess) {
        # Extract contract address from deployment output
        $contractAddressMatch = $deployOutput | Select-String -Pattern "deployed code at address (0x[0-9a-fA-F]{40})" -AllMatches
        if (-not $contractAddressMatch) {
          # Try alternative patterns that might be in the output
          $contractAddressMatch = $deployOutput | Select-String -Pattern "(0x[0-9a-fA-F]{40})" -AllMatches | Select-Object -Last 1
        }
        
        if ($contractAddressMatch) {
          $deployedContractAddress = $contractAddressMatch.Matches[0].Groups[1].Value
          if (-not $deployedContractAddress) {
            $deployedContractAddress = $contractAddressMatch.Matches[0].Value
          }
          Say "✅ Contract deployed successfully!"
          Write-Host "🎯 Contract Address: $deployedContractAddress" -ForegroundColor Green
          Write-Host "📋 Save this address - you'll need it for interacting with your contract!" -ForegroundColor Yellow
        } else {
          Say "✅ Contract deployed successfully!"
          Write-Host "⚠️ Could not extract contract address from output. Check the deployment log above." -ForegroundColor Yellow
        }
      } else {
        Say "⚠️ Contract deployment encountered errors"
        Write-Host "Error code: $LASTEXITCODE" -ForegroundColor Yellow
        $continuePushAfterDeploy = Read-Host "Do you want to push the code to GitHub despite deployment errors? (Y/N)"
        if ($continuePushAfterDeploy -ne "Y" -and $continuePushAfterDeploy -ne "y") {
          Say "⏭️ Skipping push due to deployment errors. Rust crate automation is complete locally."
          Say "🎉 Local Rust automation complete! You can deploy and push manually later."
          Write-Host "   ✅ Stylus cache SDK integration (local)"
          Write-Host "   ✅ Contract code updated (local)"
          Write-Host "   ⚠️ Manual deployment and push required"
          exit 0
        }
      }
      
      # Commit and push Rust changes
      $rustCommitMsg = Get-SmartInput "Enter commit message for Rust crate automation (or press Enter to skip): " -allowEmpty $true
      if ($rustCommitMsg) {
        docker exec $NAME bash -c "cd '$repoPath' && git add . && git commit --no-verify -m '$rustCommitMsg'" | Out-Null
        Say "✅ Rust changes committed"
        
        # Push the Rust changes
        Say "🚀 Opening new PowerShell terminal for Rust automation push..."
        $rustPushScript = @"
# Change to the project directory
cd '$((Get-Location).Path)'

# Find directory containing packages folder
`$packagesPath = Get-ChildItem -Recurse -Directory -Name "packages" -ErrorAction SilentlyContinue | Select-Object -First 1
if (`$packagesPath) {
    `$projectDir = Split-Path `$packagesPath -Parent
    if (`$projectDir -and (Test-Path `$projectDir)) {
        cd `$projectDir
        Write-Host "Navigated to project directory containing packages: `$projectDir" -ForegroundColor Green
    }
} else {
    # Fallback to speedrun-$branch directory
    if (Test-Path 'speedrun-$branch') {
        cd 'speedrun-$branch'
        Write-Host "Using speedrun project directory: speedrun-$branch" -ForegroundColor Yellow
    }
}

# Initialize git repository if it doesn't exist
if (-not (Test-Path '.git')) {
    Write-Host 'Initializing new git repository...' -ForegroundColor Yellow
    git init
}

# Set git user identity
git config user.name '$gitUserName'
git config user.email '$gitUserEmail'

# Add remote origin
git remote remove origin 2>`$null
git remote add origin '$origin'

# Ensure correct branch
git branch -M '$branch'

# Check if there are changes to commit
`$status = git status --porcelain
if (`$status) {
    Write-Host 'Changes detected. Auto-committing Rust automation changes...' -ForegroundColor Yellow
    git add .
    git commit -m 'Rust crate automation update'
    Write-Host 'Committed Rust automation changes' -ForegroundColor Green
} else {
    Write-Host 'No changes detected. Ready to push...' -ForegroundColor Green
}

# Push Rust crate automation to GitHub
Write-Host 'Pushing Rust crate automation to GitHub...' -ForegroundColor Green
git push origin '$branch'

if (`$LASTEXITCODE -eq 0) {
    Write-Host '✅ Rust crate automation pushed successfully!' -ForegroundColor Green
    Write-Host '🎉 All automation complete! Your contract now includes:' -ForegroundColor Green
    Write-Host '   ✅ Smart cache configuration' -ForegroundColor Green
    Write-Host '   ✅ Stylus cache SDK integration' -ForegroundColor Green
    Write-Host '   ✅ Optimized contract functions' -ForegroundColor Green
} else {
    Write-Host '❌ Push failed. Check your git credentials and try again.' -ForegroundColor Red
    Write-Host '⚠️ All configurations are complete locally. You can push manually later.' -ForegroundColor Yellow
    Write-Host '🎉 Local automation complete! Your contract now includes:' -ForegroundColor Green
    Write-Host '   ✅ Smart cache configuration (local)' -ForegroundColor Green
    Write-Host '   ✅ Stylus cache SDK integration (local)' -ForegroundColor Green
    Write-Host '   ✅ Optimized contract functions (local)' -ForegroundColor Green
    Write-Host '   ⚠️ Manual push required to sync with GitHub' -ForegroundColor Yellow
}

Write-Host 'Press Enter to close this terminal...' -ForegroundColor Yellow
[void](Read-Host)
"@

        # Save the push script to a temporary file
        $rustPushScriptPath = Join-Path $env:TEMP "push_rust.ps1"
        $rustPushScript | Out-File -FilePath $rustPushScriptPath -Encoding UTF8

        # Open new PowerShell terminal with the push script
        Start-Process "powershell.exe" -ArgumentList "-ExecutionPolicy", "Bypass", "-File", "`"$rustPushScriptPath`"" -WindowStyle Normal

        Say "✅ New PowerShell terminal opened for Rust automation push"
        Say "💡 Complete the push in the new terminal, then return here to continue"
        Say "⏸️  Press Enter when you're ready to continue..."
        Read-Host
      } else {
        Say "⏭️ Rust changes created but not committed. You can commit manually later."
      }
    }
  }
} else {
  Say "⏭️ Skipping Rust crate automation. You can configure it manually later if needed."
}