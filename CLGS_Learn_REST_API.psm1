Param(
    [parameter(Position = 0, Mandatory = $true)][string]$baseUrl,
    [parameter(Position = 1, Mandatory = $true)][string]$key,
    [parameter(Position = 2, Mandatory = $true)][string]$secret
)

Function getLearnRESTToken() {
    # this is a comment
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $key, $secret)))

    $requestbody = "grant_type=client_credentials"
    $oauthuri = "$baseUrl/$RESTBaseUrl/v1/oauth2/token"
    $script:numOfRequests++
    $oauthresponse = Invoke-RestMethod -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo) } -body $requestbody -Uri $oauthuri -Method Post
    Write-Log "OAuth response: $oauthresponse" "Debug"
    $script:token = $oauthresponse.access_token
    if (!$script:token) {
        Write-Error "No token found. Exiting"
        exit
    }
}

Function getRESTResponse($endpoint, $method = 'GET', $requestbody, $isFullURL = $false) {
    $started = Get-Date
    $results = [System.Collections.ArrayList]@()

    # Check if there's already a token
    if (!$script:token) {
        getLearnRESTToken
    }
    
    # Let's create a custom response object, so that we can work with this consistently in other parts of the script
    $response = [PSCustomObject]@{
        results         = $null
        headers         = $null
        error           = $null
        type            = $null
        status          = $null
        percentComplete = $null
    }
    if (!($isFullURL)) {
        $endpoint = "$baseUrl/$RESTBaseUrl/$endpoint"
    }
    Write-Log "Sending $method request to $endpoint" "Debug"
    if ($requestbody) { Write-Log "Request body: $requestbody" "Debug" }
    try { 
        $script:numOfRequests++
        $RESTresponse = Invoke-RestMethod -Headers @{Authorization = ("Bearer $script:token") } -Uri $endpoint -method $method -body $requestbody -ContentType 'application/json' -ResponseHeadersVariable responseHeader
 
        # The course copy API is supposed to return a 202 response code, with the URL to the task, but POSH doesn't parse this reponse properly
        # If the response is empty, replace it with the dictionary for the response headers, which includes all of the response details
        if (Get-Member -inputobject $RESTresponse -name "Results" -MemberType Properties) {
            Write-Log "Multiple objects returned...Adding the results to the response object" "Debug"
            foreach ($entry in $RESTresponse.results) {
                [void]$results.add($entry)
            }
        
        
            # Check if there are more pages of results
            if (get-member -InputObject $RESTresponse -name "Paging" -MemberType Properties) {
                Write-Log "There is another page of results..." "Debug"
                $hasNext = $true
                $pageURI = $RESTresponse.paging.nextPage
            }
            else {
                $hasNext = $false
            }

            while ($hasNext) {
                Write-Log $pageURI "Debug"
                $script:numOfRequests++
                $nextResponse = Invoke-RestMethod -Headers @{Authorization = ("Bearer $script:token") } -Uri $baseUrl$pageURI
                #$results.add($nextResponse.results) | Out-Null
                foreach ($entry in $nextResponse.results) {
                    [void]$results.add($entry)
                }
                Write-Log "-There are $($results.count) result sets." "Debug"
    
                if (get-member -InputObject $nextResponse -name "Paging" -MemberType Properties) {
                    Write-Log "There is another page of results..." "Debug"
                    $hasNext = $true
                    $pageURI = $nextResponse.paging.nextPage
                }
                else {
                    $hasNext = $false
                }
            }
        }
        else {
            $results = $RESTresponse
        }

        $response.results = $results
        $response.headers = $responseHeader

        # Adding in new properties that are in the task status
        if (Get-Member -inputobject $RESTresponse -name "type" -MemberType Properties) {
            $response.type = $RESTresponse.type
        }
        if (Get-Member -inputobject $RESTresponse -name "status" -MemberType Properties) {
            $response.status = $RESTresponse.status
        }
        if (Get-Member -inputobject $RESTresponse -name "percentComplete" -MemberType Properties) {
            $response.percentComplete = $RestResponse.percentComplete
        }
    }
    catch {
        $response.error = ConvertFrom-Json $_.ErrorDetails.Message
        # if ($response.error.message -notlike 'API request is not authenticated.') {
        Write-Log "Status: $($response.error.status) - $($response.error.message)" "Error"
        # }
        # else {
        # Write-Log "The copy appears to have completed: $($response.error)"
        # }
    }

    $ended = Get-Date
    $timeToComplete = New-TimeSpan -start $started -end $ended
    Write-Log "REST request completed in $timeToComplete ($script:numOfRequests total requests made, $($responseHeader.'X-Rate-Limit-Remaining'[0]))" "Debug"
    [int]$remainingRequests = $responseHeader.'X-Rate-Limit-Remaining'[0];
    if($remainingRequests % 100 -eq 0){
        Write-Log "There are $($responseHeader.'X-Rate-Limit-Remaining'[0]) requests remaining in the rate limit ($($responseHeader.'X-Rate-Limit-Limit'[0]))" "Warn"
    }
    return $response
}

Function getSingleRESTResponse($endpoint) {
    $response = getRESTResponse $endpoint
    return $response.results
}

Function getMultipleRESTResponse($endpoint) {
    $response = getRESTResponse $endpoint
    $list = @($response.results)

    $count = $list.count
    Write-Log "Found $count results"
    return $list
}

Function Get-CourseByCourseId() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][String]$courseId,
        [Parameter(Mandatory = $false, Position = 1)][String]$fields
    )
    $endpoint = "v3/courses/courseId:" + $courseid
 
    if ($fields) {
        $endpoint = $endpoint + "?" + "fields=$fields"
    }
    
    return getSingleRESTResponse $endpoint
}

Function Get-CourseSearchByCourseId() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][String]$courseIdSearchTerm,
        [Parameter(Mandatory = $false, Position = 1)][String]$fields
    )
    $endpoint = "v3/courses?courseId=$courseIdSearchTerm"
    
    if ($fields) {
        $endpoint = $endpoint + "&" + "fields=$fields"
    }
    return getMultipleRESTResponse $endpoint
}

Function Get-CourseById() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][String]$courseId,
        [Parameter(Mandatory = $false, Position = 1)][String]$fields
    )
    $endpoint = "v3/courses/" + $courseId
    
    if ($fields) {
        $endpoint = $endpoint + "?" + "fields=$fields"
    }

    return getSingleRESTResponse $endpoint
}

Function Get-Courses() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][String]$courseIdSearchTerm,
        [Parameter(Mandatory = $false, Position = 1)][String]$fields
    )
    $endpoint = "v3/courses?courseId=$courseIdSearchTerm"
    
    if ($fields) {
        $endpoint = $endpoint + "&" + "fields=$fields"
    }
    
    return getMultipleRESTResponse $endpoint
}

Function Get-DSKs() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][String]$DSKSearchTerm
    )
    $endpoint = "v1/dataSources?externalId=$DSKSearchTerm"
    return getMultipleRESTResponse $endpoint
}

Function Set-UpdateCourse() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][psobject]$course
    )
    Write-Log "Updating the name and other metadata for $($course.courseId)" "Debug"
    $endpoint = "v3/courses/$($course.id)"
    
    # Removing unneeded properties...it will throw errors if we leave them in
    $course.PSObject.Properties.Remove("courseId")
    $course.PSObject.Properties.Remove("created")
    $course.PSObject.Properties.Remove("guestAccessUrl")
    $course.PSObject.Properties.Remove("externalAccessUrl")
    $course.PSObject.Properties.Remove("readOnly")
    $course.PSObject.Properties.Remove("hasChildren")
    $course.PSObject.Properties.Remove("parentId")


    $requestbody = ConvertTo-Json $course
    getRESTResponse $endpoint "PATCH" $requestbody | out-null
}

Function Set-CreateDSK() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][string]$externalId,
        [Parameter(Mandatory = $false, Position = 1)][String]$description
    )
    Write-Log "Creating a new DSK for $externalId"
    $endpoint = "v1/dataSources"
    $dsk = [PSCustomObject]@{
        externalId  = $externalId
        description = $description
    }

    $requestbody = ConvertTo-Json $dsk
    $newDSKresponse = getRESTResponse $endpoint "POST" $requestbody
    return $newDSKresponse.response
}

Function Get-GradesByCourse() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][psobject]$course,
        [Parameter(Mandatory = $false, Position = 1)][String]$columnId = "finalGrade",
        [Parameter(Mandatory = $false, Position = 2)][String]$fields
    )
    #Get the grades for a given columns for a given course.  If no column is provided, the final (external) grade will be provided
    Write-Log "Attempting to load the grade for $($course.courseId) for column $columnId" "Debug"
    $endpoint = "v1/courses/$($course.id)/gradebook/columns/$columnId/users"
    
    if ($fields) {
        $endpoint = $endpoint + "?" + "fields=$fields"
    }
    return getMultipleRESTResponse $endpoint
}

Function Get-GradeColumnsByCourse() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][psobject]$course,
        [Parameter(Mandatory = $false, Position = 1)][String]$searchTerm,
        [Parameter(Mandatory = $false, Position = 2)][String]$fields
    )
    $endpoint = "v2/courses/$($course.id)/gradebook/columns"

    $queryParams = [System.Collections.ArrayList]@()
    if ($searchTerm) {
        [void]$queryParams.add("displayName=$searchTerm")
    }
    if ($fields) {
        [void]$queryParams.add("fields=$fields")
    }

    if ($queryParams.count -gt 0) {
        $params = $queryParams -join "&"
        $endpoint = $endpoint + "?" + $params
    }

    Write-Log "Attempting to load all of the gradebook columns for $($course.courseId)" "Debug"
    return getMultipleRESTResponse $endpoint
}

Function Get-AllUsers() {
    Write-Log "Attempting to load all of the available users" "Debug"
    $endpoint = "v1/users?availability.available=Yes"
    return getMultipleRESTResponse $endpoint
}

Function Get-CourseUsers() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][psobject]$course,
        [Parameter(Mandatory = $false, Position = 1)][String]$role,
        [Parameter(Mandatory = $false, Position = 2)][bool]$enabledOnly,
        [Parameter(Mandatory = $false, Position = 3)][bool]$fullUsers,
        [Parameter(Mandatory = $false, Position = 4)][String]$fields
    )
    Write-Log "Attempting to load the users in $($course.courseId)" "Debug"
    $endpoint = "v1/courses/$($course.id)/users"
    
    $queryParams = [System.Collections.ArrayList]@()
    if ($role) {
        [void]$queryParams.add("role=$role")
    }
    if ($enabledOnly) {
        [void]$queryParams.add("availability.available=Yes")
    }
    if ($fullUsers) {
        [void]$queryParams.add("expand=user")
    }
    if ($fields) {
        [void]$queryParams.add("fields=$fields")
    }

    if ($queryParams.count -gt 0) {
        $params = $queryParams -join "&"
        $endpoint = $endpoint + "?" + $params
    }
    return getMultipleRESTResponse $endpoint
}

Function Get-CourseUserByExternalId() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][string]$courseId,
        [Parameter(Mandatory = $true, Position = 1)][string]$userExternalId,
        [Parameter(Mandatory = $false, Position = 2)][String]$fields
    )
    Write-Log "Attempting to load the user ($userExternalId) in $($course.courseId)" "Debug"
    $endpoint = "v1/courses/externalId:" + $course.courseId + "/users/externalId:" + $userExternalId

    if ($fields) {
        $endpoint = $endpoint + "?" + "?fields=$fields"
    }

    return getSingleRESTResponse $endpoint
}

Function Get-CoursesByTerm() {
    Param(
        [Parameter(Mandatory = $false, Position = 0)][psobject]$term,
        [Parameter(Mandatory = $false, Position = 1)][String]$fields
    )
    
    if ($term.id) {
        Write-Log "Attempting to get all of the available courses for $($term.id)" "Debug"
        $endpoint = "v2/courses?availability.available=Yes&termId=$($term.id)"
    }
    elseif ($term.external_id) {
        Write-Log "Attempting to get all of the available courses for $($term.external_id)" "Debug"
        $endpoint = "v2/courses?availability.available=Yes&termId=externalId:$($term.external_id)"
    }
    else {
        Write-Log "No term found." "Error"
        return $null
    }
    if ($fields) {
        $endpoint = $endpoint + "&" + "fields=$fields"
    }
    
    return getMultipleRESTResponse $endpoint
}

Function Get-Terms() {
    Param(
        [Parameter(Mandatory = $false, Position = 0)][String]$externalId,
        [Parameter(Mandatory = $false, Position = 1)][String]$fields
    )
    $endpoint = "v1/terms"
    
    $queryParams = [System.Collections.ArrayList]@()
    if ($fields) {
        [void]$queryParams.add("fields=$fields")
    }

    if ($externalId) {
        Write-Log "Loading the terms containing $externalId" "Debug"
        [void]$queryParams.add("externalId=$externalId")
    }
    else {
        Write-Log "Loading ALL terms" "Debug"
    }

    if ($queryParams.count -gt 0) {
        $params = $queryParams -join "&"
        $endpoint = $endpoint + "?" + $params
    }
    
    
    return @(getMultipleRESTResponse $endpoint)
}

Function Get-CopyCourseByCourseId() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][String]$srcCourseId,
        [Parameter(Mandatory = $true, Position = 1)][String]$dstCourseId,
        [Parameter(Mandatory = $false, Position = 2)][Bool]$deleteEnrollments
    )
    Write-Log "Copying $srcCourseId into $dstCourseId"
    $copyEndpoint = "v2/courses/courseId:$srcCourseId/copy"
    $requestbody = "{`"targetCourse`":{`"courseId`":`"$dstCourseId`"}}"
    $response = getRESTResponse $copyEndpoint "POST" $requestbody
    
    # Check if the copy is complete
    checkTaskStatus $response.headers.location
        
    # The course copy also copies over enrollments.  We'll want to delete the enrollments from the parent course before proceeding
    if ($deleteEnrollments) {
        Set-DeleteEnrollmentsByCourseId $dstCourseId
    }
    
    # Return the newly created course to be updated with the proper metadata
    $newCourseEndpoint = "v3/courses/courseId:$dstCourseId"
    $response = getRESTResponse $newCourseEndpoint
    $newCourse = $response.results
    return $newCourse

}

Function checkTaskStatus($endpoint) {
    # Need to check and possibly update the endpoint, to work in this particular implementation
    $task_id = $endpoint.split("/")[-1]
    $endpoint = "v1/system/tasks/$task_id"
    $response = getRESTResponse $endpoint
    
    Write-Log $response "DEBUG"
    WHILE ($response.status -ne "Complete") {
        Write-Log "Waiting for the task to complete"
        start-sleep -s 10
        $response = getRESTResponse $endpoint
        Write-Log $response "DEBUG"
    }
    Write-Log "Task complete"
}

Function Set-DeleteEnrollmentsByCourseId() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][string]$courseId
    )
    Write-Log "Deleting users from $courseId"
    Write-Log "Retreiving enrollments from $courseId" "Debug"
    $endpoint = "v1/courses/courseId:$courseId/users"
    $enrollments = getMultipleRESTResponse $endpoint

    foreach ($e in $enrollments) {
        Write-Log "Deleting enrollment for $($e.userId)" "Debug"
        $endpoint = "v1/courses/courseId:$courseId/users/$($e.userId)"
        getRESTResponse $endpoint "DELETE" | Out-null
    }
}


Function Set-DeleteCourse() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][psobject]$course
    )
    Write-Log "Deleting $($course.course_id) ($($course.name))"
    $endpoint = "v3/courses/$($course.id)"
    $response = getRESTResponse $endpoint "DELETE"

    checkTaskStatus $response.headers.location
}

Function Set-AddChildCourse() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][String]$parentCourseId,
        [Parameter(Mandatory = $true, Position = 1)][String]$childCourseId
    )
    Write-Log "Adding $childCourseId to $parentCourseId"
    $endpoint = "v1/courses/courseId:$($parentCourseId)/children/courseId:$($childCourseId)?ignoreEnrollmentErrors=true"
    $response = getRESTResponse $endpoint "PUT"
    if ($response.error) {
        Write-Log $($response.error.Message) "Error"
    }
}

Function Get-ChildrenCourses() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][String]$parentCourseId
    )
    Write-Log "Retreiving the list of child courses for $parentCourseId"
    $endpoint = "v1/courses/courseId:$parentCourseId/children"
    return getMultipleRESTResponse $endpoint
}

Function Set-AddEnrollmentsByCourseId() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][String]$courseId,
        [Parameter(Mandatory = $true, Position = 1)][Array]$enrollments
    )
    foreach ($e in $enrollments) {
        Write-Log "Adding enrollment for $($e.userID)" "Debug"
        $endpoint = "v1/courses/courseId:$courseId/users/$($e.userId)"
        $body = [PSCustomObject]@{
            dataSourceId = $e.dataSourceId
            courseRoleId = $e.courseRoleId
            availability = @{available = $e.availability.available }
        }
        getRESTResponse $endpoint "PUT" ($body | ConvertTo-Json) | out-null
    }       
}

Function Set-UpdateCourseUser() {
    Param(
        [Parameter(Mandatory = $true, Position = 0)][string]$courseId,
        [Parameter(Mandatory = $true, Position = 1)][string]$userExternalId,
        [Parameter(Mandatory = $true, Position = 2)][psobject]$courseMembershipObject
    )
    $endpoint = "v1/courses/externalId:" + $course.courseId + "/users/externalId:" + $userExternalId
    getRESTResponse $endpoint "PATCH" ($courseMembershipObject | ConvertTo-Json) | out-null
}


$RESTBaseUrl = "learn/api/public"
$script:numOfRequests = 0
# This will only make the functions with hyphens in them available externally.  Other functions are internal.
Write-Log "Importing the REST module" "Debug"
Export-ModuleMember *-*