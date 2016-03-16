
#*********************************************************************
# Preparing for analysing the Logs
#*********************************************************************

# Structures for tracking the applications

#Map ID -> App Name for drawing the image
$AppNames = New-Object String[] 64 

#Map App Name -> ID for initial application discovery process
$AppHash = @{}

#Counter for discovered applications
$AppCount = 0


#Output all discovered transactions to a log file for outside analysis
$LogFolder = ".\"
$LogFiles = Get-ChildItem $LogFolder | where {$_.extension -eq ".log"}
$OutputLog = ".\transactions.csv"

if(Test-Path $OutputLog)
{
	Clear-Content $OutputLog
}
else
{
	New-Item $OutputLog -type file | Out-Null
}
Add-Content $OutputLog "Robot, Application, StartDate, EndDate, Duration, Successful"
$NumberOfRobots = $LogFiles.Length


# Structures for tracking the transactions
$SecondsInADay = 86400
$Schedule = New-Object 'Byte[,] '$NumberOfRobots,$SecondsInADay

# Bit masks used to define data format of $Schedule:

# Bit mask used to identify whether a transaction was running during a second
$RunningBM = [Byte] 0x80
# Bit mask used to identify if a transaction running was successful or failed.
$FailureBM = [Byte] 0x40
# Bit mask used to identify the generated ID of the application
$AppNameBM = [Byte] 0x3F


# Date related variables
$StartDate = Get-Date
$Midnight = (Get-Date).Date



#*********************************************************************
# Analysing the Logs
#*********************************************************************

for($x = 0; $x -lt $NumberOfRobots; $x++)
{
	$LogPath = $LogFiles[$x]
		
	#Locally track when a transaction started
	$StartSeconds = 0
	
	# Read and parse log to find key events for starting and ending transactions
	Write-Output ("{0:D2}: Parsing $LogPath" -f ($x + 1))
		
	
	# Process parsed events to build the schedule for the day	
	$reader = New-Object System.IO.StreamReader -Arg $LogPath
	
	while ($Event = $reader.ReadLine()) 
	{
		# Transaction started
		if($Event -match ".*App: ?([\w]*) Started. - ([0-9]?[0-9]:[0-9][0-9]:[0-9][0-9] [AP]M).*")
		{
			$AppName = $matches[1]
			if(-Not $AppHash.ContainsKey($AppName))
			{
				$AppHash.Add($AppName, $AppCount)
				$AppNames[$AppCount] = $AppName
				$AppCount++
				
				Write-Output "AppName: $($AppName):  $($AppHash.Get_Item($AppName))"
			}
			$StartDate = [datetime]$matches[2]
			$StartSeconds = (New-TimeSpan -Start $StartDate.Date -End $StartDate).totalSeconds
		}
		
		# Transaction ended successfully
		if($Event -match ".*App: ?([\w]*) Ended. - ([0-9]?[0-9]:[0-9][0-9]:[0-9][0-9] [AP]M).*")
		{
			$AppName = $matches[1]
			$EndDate = [datetime]$matches[2]
			$EndSeconds = (New-TimeSpan -Start $EndDate.Date -End $EndDate).totalSeconds
			$Duration = (New-TimeSpan -Start $StartDate -End $EndDate).totalSeconds
			$AppID = $AppHash.Get_Item($AppName)
			
			$Seconds = $StartSeconds..$EndSeconds | ForEach-Object {$Schedule[$x,$_] = [Byte]$RunningBM -bor [Byte] $AppID}
			Add-Content $OutputLog "$LogPath, $AppName, $StartDate, $EndDate, $Duration,  TRUE"
		}
		
		#Transaction ended with failure
		if($Event -match ".*App: ?([\w]*) ERRORED. - ([0-9]?[0-9]:[0-9][0-9]:[0-9][0-9] [AP]M).*")
		{
			$AppName = $matches[1]
			$EndDate = [datetime]$matches[2]
			$EndSeconds = (New-TimeSpan -Start $EndDate.Date -End $EndDate).totalSeconds
			$Duration = (New-TimeSpan -Start $StartDate -End $EndDate).totalSeconds
			$AppID = $AppHash.Get_Item($AppName)
			
			$Seconds = $StartSeconds..$EndSeconds | ForEach-Object {$Schedule[$x,$_] = ([Byte]$RunningBM -bor [Byte] $AppID) -bor [Byte] $FailureBM}
			Add-Content $OutputLog "$LogPath, $AppName, $StartDate, $EndDate, $Duration, FALSE"
		}
	}
	Write-Output ("{0:D2}: Parsing finished" -f ($x + 1))
}



#*********************************************************************
# Preparing for Drawing the Images
#*********************************************************************
$StartCount = New-Object Int[] $NumberOfRobots
$CurrentStartSeconds = New-Object Int[] $NumberOfRobots
#Whether a robot has continued a transaction over the period boundary
$Continued = New-Object Int[] $NumberOfRobots
$CurrentState = New-Object Byte[] $NumberOfRobots
$Hour = 0

[System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") | Out-Null

#Constants for sizing the image

#Total width of the column
$ColumnWidth = 500
$leftOffset = 200
$TopOffset = 100
#Width to subtract from $ColumnWidth for displaying whether a transaction failed
$StatusWidth = 50

$AppWidth = $ColumnWidth - $StatusWidth
#Number of seconds per output image.
$DisplayLength = 3600

$BMPWidth = $NumberOfRobots * $ColumnWidth + $leftOffset
$BMPHeight = ($TopOffset + $DisplayLength)
# Constants for Drawing Headers and Lines
$LeftBrush =  [System.Drawing.Brushes]::White
$LinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black)
$LinePen.Width = 1
$VerticalLinePen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black)
$VerticalLinePen.Width = 5

#Constants for drawing comments
$CommentFont = New-Object System.Drawing.Font("Segoe UI", 14)
$MinuteFont = New-Object System.Drawing.Font("Segoe UI", 14)
$MiniCommentFont = New-Object System.Drawing.Font("Segoe UI", 8)
$CommentBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 0, 0,0))

#Constants for drawing transaction status
$brushSuccessful = [System.Drawing.Brushes]::Green
$brushFailed = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 192, 0, 0))
$brushNotRunning = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 192, 192, 192))

#Constants for individual applications
$AppColors = New-Object 'System.Drawing.SolidBrush[]' 10
$AppColors[0] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 192, 000, 000))
$AppColors[1] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 192, 096, 000))
$AppColors[2] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 192, 192, 000))
$AppColors[3] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 000, 192, 000))
$AppColors[4] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 000, 192, 144))
$AppColors[5] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 000, 192, 192))
$AppColors[6] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 000, 096, 192))
$AppColors[7] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 000, 000, 192))
$AppColors[8] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 096, 000, 192))
$AppColors[9] = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 192, 000, 192))


#*********************************************************************
# Drawing the Images
#*********************************************************************

$BMP = New-Object System.Drawing.Bitmap ($BMPWidth, $BMPHeight)
$Image = [System.Drawing.Graphics]::FromImage($BMP)

for($y = 0; $y -lt $SecondsInADay; $y++)	
{
	if($y % $DisplayLength -eq 0)
	{
		$PeriodStart = $Midnight.AddSeconds($y - $DisplayLength)
		$PeriodEnd = $Midnight.AddSeconds($y)
		if($y -gt 0)
		{
			for($x = 0; $x -lt $NumberOfRobots; $x++)
			{
			#If a transaction crosses the hour boundary, close out the rectangle
				if($CurrentState[$x] -ne ([byte] 0x00))
				{
					if (($Schedule[$x,($y-1)] -Band [Byte] $FailureBM) -ne [Byte]0x00)
					{
						Write-Output "Wrap Failed"
						$Image.FillRectangle($brushFailed,$leftOffset+ $x * $ColumnWidth + 2,$TopOffset + ($StartCount[$x] % $DisplayLength),$StatusWidth,($y - 1) % $DisplayLength)
					}
					else
					{
						Write-Output "Wrap Successful"
						$Image.FillRectangle($brushSuccessful,$leftOffset+ $x * $ColumnWidth + 2,$TopOffset + ($StartCount[$x] % $DisplayLength),$StatusWidth,($y - 1) % $DisplayLength)
					}
					$Image.FillRectangle($AppColors[($Schedule[($x),($y-1)] -bAnd [Byte]$AppNameBM) % 10],$leftOffset + $x * $ColumnWidth + 2 + $StatusWidth,$TopOffset + ($StartCount[$x] % $DisplayLength),$AppWidth - 5,($y - 1) % $DisplayLength)
					
					$TextString = $($AppNames[($Schedule[$x,$y] -band $AppNameBM)])
					
					$Image.DrawString("$TextString (Continues on next image)", $CommentFont, $CommentBrush, $leftOffset + $x * $ColumnWidth + 2 + $StatusWidth, $TopOffset + ($StartCount[$x] % $DisplayLength) + 2)
					$Continued[$x] = 1
					
				}
				#If no transaction crosses the hour boundary
				else
				{
					#Write-Output "Test EQ NOT 80"
					$image.FillRectangle($brushNotRunning,$leftOffset + $x * $ColumnWidth + 2+$StatusWidth,$TopOffset + $StartCount[$x] % $DisplayLength,$AppWidth - 5,($y - 1) % $DisplayLength)
					$Image.FillRectangle($brushSuccessful,$leftOffset+ $x * $ColumnWidth + 2,$TopOffset + ($StartCount[$x] % $DisplayLength),$StatusWidth,($y - 1) % $DisplayLength)
					
				}
				$StartCount[$x] = $y
				#Write-Output $StartCount[$x]
			}
			for($z = 0; $z -le $DisplayLength; $z += 900)
			{
				$StartPoint = New-Object System.Drawing.Point ( 0, ($TopOffset + ($z)))
				$EndPoint = New-Object System.Drawing.Point ( ($BMP.Width-1), ($TopOffset + ($z)) )
				$Image.DrawLine($VerticalLinePen,$StartPoint, $EndPoint)
			}
			$Image.Dispose()
			
			
			$Output = "Saved chart for {0:hh:mm tt}" -f $PeriodStart
			$Output = "$Output - {0:hh:mm tt}" -f $PeriodEnd
			Write-Output $Output
			$BMP.Save(".\Output\output$Hour.png","PNG")
			
			$BMP = New-Object System.Drawing.Bitmap ($BMPWidth, ( $TopOffset + $DisplayLength))
			$Image = [System.Drawing.Graphics]::FromImage($BMP)
			$Hour++
			
		}
		$RobotFont = new-object System.Drawing.Font("Segoe UI", 24)
		#Wrapping up the previous image and starting a new image
		for($x = 0; $x -lt $NumberOfRobots; $x++)
		{
			
			$Image.DrawString($LogFiles[$x].BaseName, $RobotFont, $CommentBrush, $LeftOffset + 10 + $x * $ColumnWidth, 10) 
			$StartPoint = New-Object System.Drawing.Point ( ($leftOffset + ($x * $ColumnWidth) - 1), 0)
			$EndPoint = New-Object System.Drawing.Point ( ($leftOffset + ($x * $ColumnWidth) - 1), ($TopOffset + $DisplayLength - 1) )
			$Image.DrawLine($VerticalLinePen,$StartPoint, $EndPoint)
			
		}
		$Image.DrawString("{0:hh:mm tt}" -f $PeriodEnd, $RobotFont, $CommentBrush, 10, 10)
		$StartPoint = New-Object System.Drawing.Point ( ($leftOffset + ($NumberOfRobots * $ColumnWidth) - 1), 0)
			$EndPoint = New-Object System.Drawing.Point ( ($leftOffset + ($NumberOfRobots * $ColumnWidth) - 1), ($TopOffset + $DisplayLength - 1) )
			$Image.DrawLine($VerticalLinePen,$StartPoint, $EndPoint)
		
	}
	#Draw lines and text for each minute
	if($y % 60 -eq 0)
	{
		#Write-Output "Drawing Line (0, $($y % $DisplayLength)), ($leftOffset, $($y % $DisplayLength))"
		$StartPoint = New-Object System.Drawing.Point ( 0, ($TopOffset + ($y % $DisplayLength)))
		$EndPoint = New-Object System.Drawing.Point ( $leftOffset, ($TopOffset + ($y % $DisplayLength)) )
		$Image.DrawLine($LinePen,$StartPoint, $EndPoint)
		$CurrentTime = "{0:hh:mm tt}" -f $($Midnight.AddSeconds($y))
		$Image.DrawString($CurrentTime, $MinuteFont, $CommentBrush, 90, $TopOffset + ($y % $DisplayLength ) + 15)
		if($y % 900 -eq 0)
		{
			$Image.DrawLine($VerticalLinePen,$StartPoint, $EndPoint)
		}
	}
	
	#If a transaction starts, or stops...
	for($x = 0; $x -lt $NumberOfRobots; $x++)
	{
		#Write-Host "Schedule $($Schedule[$x,$y]) BAND $([Byte]$Schedule[$x,$y] -Band [Byte]$RunningBM) CurrentState $($CurrentState[$x])"
		
		if(($Schedule[$x,$y] -Band [Byte]$RunningBM) -ne [Byte]0x00)
		{
			#Write-Host -NoNewLine "O"
			if($CurrentState[$x] -eq [Byte] 0x00)
			{
				#Close off Previous No Transaction
				#Write-Output "Started at $y"
				$Image.FillRectangle($brushNotRunning,$leftOffset+ $x * $ColumnWidth + 2 + $StatusWidth,$TopOffset + ($StartCount[$x] % $DisplayLength), $AppWidth - 5,($y) % $DisplayLength)
				$Image.FillRectangle($brushSuccessful,$leftOffset+ $x * $ColumnWidth + 2,$TopOffset + ($StartCount[$x] % $DisplayLength),$StatusWidth,($y) % $DisplayLength)
				$StartCount[$x] = $y % $DisplayLength
				$CurrentStartSeconds[$x] = $y
				#When On, Current State = 128 only
				$CurrentState[$x] = [Byte] $RunningBM
				
			}
		}
		else
		{	
			#Write-Host -NoNewLine "@"
			if($CurrentState[$x] -ne [Byte] 0x00)
			{
				#Close off transaction
				# Write-Output "Ended at $y"
				#Write-Output "$($StartCount[$x]) - $($y): Finished On, Now Off"
				$image.FillRectangle($AppColors[($Schedule[($x),($y-1)] -bAnd [Byte]$AppNameBM) % 10],$leftOffset + $x * $ColumnWidth + 2 + $StatusWidth,$TopOffset + ($StartCount[$x] % $DisplayLength),$AppWidth - 5,($y) % $DisplayLength)
				if (($Schedule[$x,($y-1)] -Band [Byte] $FailureBM) -ne [Byte]0x00)
				{
					#Failed Transaction
					#Write-Output "FailedTransaction"
					$Image.FillRectangle($brushFailed,$leftOffset+ $x * $ColumnWidth + 2,$TopOffset + ($StartCount[$x] % $DisplayLength),$StatusWidth,($y) % $DisplayLength)
				}
				else
				{
					$Image.FillRectangle($brushSuccessful,$leftOffset+ $x * $ColumnWidth + 2,$TopOffset + ($StartCount[$x] % $DisplayLength),$StatusWidth,($y) % $DisplayLength)
				}
				$StartTime = $Midnight.AddSeconds($CurrentStartSeconds[$x])
				$EndTime = $Midnight.AddSeconds($y)
				$TimeSpan = New-TimeSpan -Start $StartTime -End $EndTime
				
				$TextString = $AppNames[($Schedule[($x),($y-1)] -bAnd [Byte]$AppNameBM)]
				$TextString = "$TextString {0:hh:mm:ss}" -f $StartTime
				$TextString = "$TextString - {0:hh:mm:ss}" -f $EndTime
				$TextString = "$TextString ($( [int]$TimeSpan.Minutes)m, $([int]$TimeSpan.Seconds)s)"
				
				#Write-Output "ScheduleApp $($Schedule[$x,($y-1)]) AppNameBM $AppNameBM) Result $($Schedule[$x,($y-1)] -band $AppNameBM) AppName $($AppNames[($Schedule[$x,($y-1)] -band $AppNameBM)])"
				#Write-Output "TextString: $TextString $($Schedule[($x1),$y])"
				if($Continued[$x] -eq 1)
				{
					$TextString = "(Continued) $TextString"
					#$Continued[$x] = 0
				}
				if($TimeSpan.TotalSeconds -lt 80)
				{
					$Image.DrawString($TextString, $MiniCommentFont, $CommentBrush, $leftOffset + 2 + $StatusWidth + $x * $ColumnWidth,$TopOffset + ($StartCount[$x] % $DisplayLength) + 2)
				}
				else
				{
					$Image.DrawString($TextString, $CommentFont, $CommentBrush, $leftOffset + 2 + $StatusWidth + $x * $ColumnWidth,$TopOffset + ($StartCount[$x] % $DisplayLength) + 2)
				}
				$StartCount[$x] = $y % $DisplayLength
				$CurrentState[$x] = [Byte] 0x00
				#Write-Output "$y: Finished Off, Now On"
			}
		}
	}
}



# Final Image - Wrap Up last element
$PeriodStart = $Midnight.AddSeconds($y - $DisplayLength)
$PeriodEnd = $Midnight.AddSeconds($y)
$Output = "Saved chart for {0:hh:mm tt}" -f $PeriodStart
$Output = "$Output - {0:hh:mm tt}" -f $PeriodEnd
Write-Output $Output
for($x = 0; $x -lt $NumberOfRobots; $x++)
{
	if($CurrentState[$x] -ne ([byte] 0x00))
	{
		$Image.FillRectangle($AppColors[($Schedule[($x),($y-1)] -bAnd [Byte]$AppNameBM) % 10],$leftOffset + $x * $ColumnWidth+2,$TopOffset + ($StartCount[$x] % $DisplayLength),$ColumnWidth - 5,($y - 1) % $DisplayLength)
		$Image.DrawString("$($AppNames[($Schedule[$x,$y] -band $AppNameBM)])", $CommentFont, $CommentBrush, $leftOffset + 10,$TopOffset +  ($StartCount[$x] % $DisplayLength) + 10)	
	}
	else
	{
		#Write-Output "Test EQ NOT 80"
		$image.FillRectangle($brushNotRunning,$leftOffset + $x * $ColumnWidth + 2,$TopOffset + $StartCount[$x] % $DisplayLength,$ColumnWidth - 5,($y - 1) % $DisplayLength)
	}
}
for($z = 0; $z -le $DisplayLength; $z += 900)
	{
		$StartPoint = New-Object System.Drawing.Point ( 0, ($TopOffset + ($z)))
		$EndPoint = New-Object System.Drawing.Point ( ($BMP.Width-1), ($TopOffset + ($z)) )
		$Image.DrawLine($VerticalLinePen,$StartPoint, $EndPoint)
	}
$Image.Dispose()
$BMP.Save(".\Output\output$Hour.png","PNG")






