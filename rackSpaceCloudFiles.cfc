<cfcomponent name="RackSpaceCloudFiles" displayName="RackSpace CloudFiles REST Wrapper">


<cfset this.user = "">
<cfset this.key = "">
<cfset this.authUrl = "https://auth.api.rackspacecloud.com/v1.0">
<cfset this.storageUrl = "">
<cfset this.deliveryUrl = "">
<cfset this.authToken = "">
<cfset this.authorized = false>
<cfset this.verbose = false>
<cfset this.mimeTypes = {
		htm = "text/html"
	,	html = "text/html"
	,	js = "application/x-javascript"
	,	txt = "text/plain"
	,	xml = "text/xml"
	,	rss = "application/rss+xml"
	,	css = "text/css"
	,	gz = "application/x-gzip"
	,	gif = "image/gif"
	,	jpe = "image/jpeg"
	,	jpeg = "image/jpeg"
	,	jpg = "image/jpeg"
	,	png = "image/png"
	,	swf = "application/x-shockwave-flash"
	,	ico = "image/x-icon"
	,	flv = "video/x-flv"
	,	xls = "application/msword"
	,	xls = "application/vnd.ms-excel"
	,	pdf = "application/pdf"
	,	svg = "image/svg+xml"
	,	eot = "application/vnd.ms-fontobject"
	,	ttf = "font/ttf"
	,	otf = "font/opentype"
	,	woff = "application/font-woff"
	,	woff2 = "font/woff2"
}>


<cffunction name="init" access="public" returnType="rackSpaceCloudFiles" output="false"
		hint="Returns an instance of the CFC initialized.">
	
	<cfargument name="user" type="string" required="true" hint="">
	<cfargument name="key" type="string" required="true" hint="">
	<cfargument name="preAuth" type="boolean" default="false">
	<cfargument name="httpTimeOut" type="numeric" default="300">
	<cfargument name="verbose" type="boolean" default="false">
	
	<cfset this.user = arguments.user>
	<cfset this.key = arguments.key>
	<cfset this.httpTimeOut = arguments.httpTimeOut>
	<cfset this.verbose = arguments.verbose>
	
	<!--- method renaming --->
	<cfset this.createObject = this.putObject>
	<cfset this.createFileObject = this.putFileObject>
	<cfset this.createFileObjects = this.putFileObjects>
	<cfset this.createDirectory = this.putDirectory>
	<cfset this.createContainer = this.putContainer>
	
	<cfif arguments.preAuth>
		<cfset authenticate()>
	</cfif>
	
	<cfreturn this>
</cffunction>


<cffunction name="getFileMimeType" returnType="string" output="false">
	<cfargument name="filePath" type="string" required="true">
	 
	<cfset var contentType = "">
	
	<cfif NOT len( arguments.filePath )>
		<!--- do nothing --->
	<cfelseif structKeyExists( this.mimeTypes, listLast( arguments.filePath, "." ) )>
		<cfset contentType = this.mimeTypes[ listLast( arguments.filePath, "." ) ]>
	<cfelse>
		<cftry>
		 	<cfset contentType = getPageContext().getServletContext().getMimeType( arguments.filePath )>
			<cfcatch>
				<cfset contentType = "">
			</cfcatch>
		</cftry>
	 	<cfif NOT isDefined( "contentType" )>
			<cfset contentType = "">
		</cfif>
	</cfif>
	 
	<cfreturn contentType>
</cffunction>


<cffunction name="MD5inHex" returnType="string" access="public" output="false"
	description="Generate RSA MD5 hash"
>
	<cfargument name="content" type="any" required="true">
	
	<cfset var result = 0>
	<cfset var digest = createObject( "java", "java.security.MessageDigest" )>
	<cfset digest = digest.getInstance( "MD5" )>
	
	<cfif isSimpleValue( arguments.content )>
		<cfset result = digest.digest( arguments.content.getBytes() )>
	<cfelse>
		<cfset result = digest.digest( arguments.content )>
	</cfif>
	
	<cfreturn lCase( binaryEncode( binaryDecode( toBase64( result ), "base64" ), "hex" ) )>
</cffunction>


<cffunction name="authenticate" access="public" output="false" returnType="struct" 
		description="">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "", authToken = "", storageUrl = "", deliveryUrl = "" }>
	
	<cfset arguments.method = "GET">
	<cfset arguments.url = "#this.authUrl#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-User" value="#this.user#">
		<cfhttpparam type="header" name="X-Auth-Key" value="#this.key#">
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "204">
		<!--- success --->
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
		<cfif structKeyExists( http.responseHeader, "X-Auth-Token" )>
			<cfset response.authToken = http.responseHeader[ "X-Auth-Token" ]>
		</cfif>
		<cfif structKeyExists( http.responseHeader, "X-Storage-Url" )>
			<cfset response.storageUrl = http.responseHeader[ "X-Storage-Url" ]>
		</cfif>
		<cfif structKeyExists( http.responseHeader, "X-CDN-Management-Url" )>
			<cfset response.deliveryUrl = http.responseHeader[ "X-CDN-Management-Url" ]>
		</cfif>
		<cfset this.authorized = true>
		<cfset this.authToken = response.authToken>
		<cfset this.storageUrl = response.storageUrl>
		<cfset this.deliveryUrl = response.deliveryUrl>
	<cfelse>
		<cfset deauthenticate()>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="deauthenticate" access="public" output="false" 
		description="Remove authenticated token/urls">

	<cfset this.storageUrl = "">
	<cfset this.deliveryUrl = "">
	<cfset this.authToken = "">
	<cfset this.authorized = false>
	
	<cfreturn>
</cffunction>


<cffunction name="getAccountInfo" access="public" output="false" returnType="struct" 
		description="Return the number of containers and total size of all containers.">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "", containers = "", bytes = 0 }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "HEAD">
	<cfset arguments.url = "#this.storageUrl#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "204">
		<!--- no containers --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
		<cfif structKeyExists( http.responseHeader, "X-Account-Container-Count" )>
			<cfset response.containers = http.responseHeader[ "X-Account-Container-Count" ]>
		</cfif>
		<cfif structKeyExists( http.responseHeader, "X-Account-Total-Bytes-Used" )>
			<cfset response.bytes = http.responseHeader[ "X-Account-Total-Bytes-Used" ]>
		</cfif>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="getContainers" access="public" output="false" returnType="struct" 
		description="List all available containers.">
	
	<cfargument name="limit" type="numeric" default="10000">
	<cfargument name="marker" type="string" default="">
	<cfargument name="format" type="string" default="">
	<cfargument name="cdn" type="boolean" default="true">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "", containers = "" }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "GET">
	<cfif arguments.cdn>
		<cfset arguments.url = "#this.deliveryUrl#">
	<cfelse>
		<cfset arguments.url = "#this.storageUrl#">
	</cfif>
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
		<cfif arguments.cdn>
			<cfhttpparam type="url" name="enabled_only" value="true">
		</cfif>
		<cfif arguments.format IS "json" OR arguments.format IS "xml">
			<cfhttpparam type="url" name="format" value="#arguments.format#">
		</cfif>
		<cfif arguments.limit GT 0>
			<cfhttpparam type="url" name="limit" value="#arguments.limit#">
		</cfif>
		<cfif len( arguments.marker )>
			<cfhttpparam type="url" name="marker" value="#arguments.marker#">
		</cfif>
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "204">
		<!--- no containers --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
	</cfif>
	
	<cfif len( http.fileContent )>
		<cfif arguments.format IS "json">
			<cfset response.containers = deserializeJSON( http.fileContent, true )>
		<cfelseif arguments.format IS "xml">
			<cfset response.containers = xmlParse( http.fileContent )>
		<cfelseif arguments.format IS "array">
			<cfset response.containers = listToArray( http.fileContent, chr(13) & chr(10) )>
		<cfelseif arguments.format IS "list">
			<cfset response.containers = listChangeDelims( http.fileContent, chr(13) & chr(10), "," )>
		<cfelse>
			<cfset response.containers = http.fileContent>
		</cfif>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="getContainer" access="public" output="false" returnType="struct" 
		description="Get a container.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="limit" type="numeric" default="-1">
	<cfargument name="marker" type="string" default="">
	<cfargument name="prefix" type="string" default="">
	<cfargument name="format" type="string" default="">
	<cfargument name="directory" type="string" default="">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "", objects = "" }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "GET">
	<cfset arguments.url = "#this.storageUrl#/#arguments.container#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
		<cfif arguments.limit GT 0>
			<cfhttpparam type="url" name="limit" value="#arguments.limit#">
		</cfif>
		<cfif len( arguments.marker )>
			<cfhttpparam type="url" name="marker" value="#arguments.marker#">
		</cfif>
		<cfif len( arguments.prefix )>
			<cfhttpparam type="url" name="prefix" value="#arguments.prefix#">
		</cfif>
		<cfif arguments.format IS "json" OR arguments.format IS "xml">
			<cfhttpparam type="url" name="format" value="#arguments.format#">
		</cfif>
		<cfif len( arguments.directory )>
			<cfhttpparam type="url" name="path" value="#arguments.directory#">
		</cfif>
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "204">
		<!--- Container empty --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "failed, unauthorized">
	<cfelseif http.responseHeader.Status_Code IS "404">
		<cfset response.error = "container '#arguments.container#' not found">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
		<cfif len( http.fileContent )>
			<cfif arguments.format IS "json">
				<cfset response.objects = deserializeJSON( http.fileContent, true )>
			<cfelseif arguments.format IS "xml">
				<cfset response.objects = xmlParse( http.fileContent )>
			<cfelseif arguments.format IS "array">
				<cfset response.containers = listToArray( http.fileContent, chr(13) & chr(10) )>
			<cfelseif arguments.format IS "list">
				<cfset response.containers = listChangeDelims( http.fileContent, chr(13) & chr(10), "," )>
			<cfelse>
				<cfset response.objects = http.fileContent>
			</cfif>
		</cfif>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="getContainerInfo" access="public" output="false" returnType="struct" 
		description="Return the number of objects and total size of the container.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="cdnInfo" type="boolean" default="false">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "", containers = 0, bytes = 0 }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "HEAD">
	<cfset arguments.url = "#this.storageUrl#/#arguments.container#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "204">
		<!--- Container empty --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "failed, unauthorized">
	<cfelseif http.responseHeader.Status_Code IS "404">
		<cfset response.error = "container '#arguments.container#' not found">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
		<cfif structKeyExists( http.responseHeader, "X-Account-Container-Count" )>
			<cfset response.containers = http.responseHeader[ "X-Account-Container-Count" ]>
		</cfif>
		<cfif structKeyExists( http.responseHeader, "X-Account-Total-Bytes-Used" )>
			<cfset response.bytes = http.responseHeader[ "X-Account-Total-Bytes-Used" ]>
		</cfif>
		<cfif arguments.cdnInfo>
			<cfset response.cdnResponse = getContainerCDNInfo( arguments.container )>
			<cfset response.cdnEnabled = response.cdnResponse.cdnEnabled>
			<cfset response.cdnURI = response.cdnResponse.cdnURI>
			<cfset response.cdnTTL = response.cdnResponse.cdnTTL>
			<cfset response.success = response.cdnResponse.success>
			<cfset response.error = response.cdnResponse.error>
		</cfif>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="getContainerCDNInfo" access="public" output="false" returnType="struct" 
		description="Return the CDN settings of a container.">
	
	<cfargument name="container" type="string" required="true">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "", cdnEnabled = false, cdnURI = "", cdnTTL = "" }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "HEAD">
	<cfset arguments.url = "#this.deliveryUrl#/#arguments.container#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "204">
		<!--- Container empty --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif http.responseHeader.Status_Code IS "404">
		<cfset response.error = "container '#arguments.container#' not found">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
		<cfif structKeyExists( http.responseHeader, "X-CDN-Enabled" )>
			<cfset response.cdnEnabled = http.responseHeader[ "X-CDN-Enabled" ]>
		</cfif>
		<cfif structKeyExists( http.responseHeader, "X-CDN-URI" )>
			<cfset response.cdnURI = http.responseHeader[ "X-CDN-URI" ]>
		</cfif>
		<cfif structKeyExists( http.responseHeader, "X-TTL" )>
			<cfset response.cdnTTL = http.responseHeader[ "X-TTL" ]>
		</cfif>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="putContainer" access="public" output="false" returnType="struct" 
		description="Creates a container.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="cdnEnabled" type="string" default="false">
	<cfargument name="ttl" type="string" default="">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "" }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "PUT">
	<cfset arguments.url = "#this.storageUrl#/#arguments.container#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "201">
		<!--- Container created --->
	<cfelseif http.responseHeader.Status_Code IS "202">
		<!--- Container already exists --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
		<!--- enable CDN distribution --->
		<cfif arguments.cdnEnabled>
			<cfset response.cdnResponse = updateContainer( arguments.container, arguments.cdnEnabled, arguments.ttl )>
			<cfset response.cdnURI = response.cdnResponse.cdnURI>
			<cfset response.success = response.cdnResponse.success>
			<cfset response.error = response.cdnResponse.error>
		</cfif>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="deleteContainer" access="public" output="false" returnType="struct" 
		description="Deletes a container.">
	
	<cfargument name="container" type="string" required="true">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "" }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "DELETE">
	<cfset arguments.url = "#this.storageUrl#/#arguments.container#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "204">
		<!--- Success --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif http.responseHeader.Status_Code IS "404">
		<cfset response.error = "container '#arguments.container#' not found">
	<cfelseif http.responseHeader.Status_Code IS "409">
		<cfset response.error = "failed, '#arguments.container#' is not empty">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="updateContainer" access="public" output="false" returnType="struct" 
		description="Updates a container on the content delivery network.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="cdnEnabled" type="string" default="true">
	<cfargument name="ttl" type="string" default="">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "", cdnURI = "" }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "PUT">
	<cfset arguments.url = "#this.deliveryUrl#/#arguments.container#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
		<cfhttpparam type="header" name="X-CDN-Enabled" value="#arguments.cdnEnabled#">
		<cfif len( arguments.ttl )>
			<cfhttpparam type="header" name="X-TTL" value="#arguments.ttl#">
		</cfif>
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "202">
		<!--- Updated successfully --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif http.responseHeader.Status_Code IS "404">
		<cfset response.error = "container '#arguments.container#' not found">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
		<cfif structKeyExists( http.responseHeader, "X-CDN-URI" )>
			<cfset response.cdnURI = http.responseHeader[ "X-CDN-URI" ]>
		</cfif>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="putDirectory" access="public" output="false" returnType="struct"
		description="Puts a virtual directory into a container.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="directory" type="string" required="true">
	<cfargument name="metadata" type="struct" default="#{}#">
	
	<cfreturn putObject( arguments.container, arguments.directory, "", "application/directory", 0, "", arguments.metadata )>
</cffunction>


<cffunction name="putFileObject" access="public" output="false" returnType="struct"
		description="Puts an object into a container.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="key" type="string" required="true">
	<cfargument name="file" type="string" required="true">
	<cfargument name="type" type="string" required="true" default="auto">
	<cfargument name="md5" type="string" default="">
	<cfargument name="metadata" type="struct" default="#{}#">
	
	<cfif arguments.type IS "auto">
		<cfset arguments.type = getFileMimeType( arguments.file )>
	</cfif>
	
	<cfset arguments.content = fileReadBinary( arguments.file )>
	<cfset arguments.length = arrayLen( arguments.content )>
	
	<cfreturn putObject( argumentCollection = arguments )>
</cffunction>


<cffunction name="putFileObjects" access="public" output="false" returnType="struct"
	description="Puts an query of objects into a container."
>
	<cfargument name="container" type="string" required="true">
	<cfargument name="query" type="query" required="true">
	<cfargument name="threads" type="numeric" default="1">
	<cfargument name="md5" type="string" default="auto">
	<cfargument name="metaData" type="struct" default="#{}#">
	
	<cfset var response = { success = true }>
	
	<cfscript>
		queryEach( arguments.query, function( r ) {
			var out= 0;
			if( !find( ".", ATTRIBUTES.filename ) ) {
				out= this.putDirectory(
					container= r.container
				,	directory= r.storageKey
				,	metaData= r.metaData
				);
			} else {
				out= this.putFileObject(
					container= r.container
				,	key= r.storageKey
				,	file= r.filename
				,	metaData= r.metaData
				,	type= "auto"
				,	md5= r.md5
				);
			}
			response[ r.storageKey ] = out;
			if( !out.success ) {
				response.success = false;
			}
		}, ( arguments.threads > 1 ), arguments.threads );
	</cfscript>
	
	<cfreturn response>
</cffunction>


<cffunction name="putObject" access="public" output="false" returnType="struct"
		description="Puts an object into a container.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="key" type="string" required="true">
	<cfargument name="content" type="any" required="true">
	<cfargument name="type" type="string" default="">
	<cfargument name="length" type="numeric" required="false">
	<cfargument name="md5" type="string" default="">
	<cfargument name="metadata" type="struct" default="#{}#">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "" }>
	<cfset var item = "">
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "PUT">
	<cfset arguments.url = "#this.storageUrl#/#arguments.container#/#arguments.key#">
	
	<cfif arguments.md5 IS "auto">
		<cfset arguments.md5 = MD5inHex( arguments.content )>
	</cfif>
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
		<cfif len( arguments.type )>
			<cfhttpparam type="header" name="Content-Type" value="#arguments.type#">
		</cfif>
		<cfif structKeyExists( arguments, "length" ) AND len( arguments.length )>
			<cfhttpparam type="header" name="Content-Length" value="#arguments.length#">
		</cfif>
		<!--- <cfhttpparam type="header" name="Transfer-Encoding" value="chunked"> --->
		<cfloop collection="#arguments.metadata#" item="item">
			<cfhttpparam type="header" name="X-Object-Meta-#item#" value="#arguments.metadata[ item ]#">
		</cfloop>
		<cfif len( arguments.md5 )>
			<cfhttpparam type="header" name="ETag" value="#arguments.md5#">
		</cfif>
		<cfhttpparam type="body" value="#arguments.content#">
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "201">
		<!--- Success, created --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif http.responseHeader.Status_Code IS "412">
		<cfset response.error = "failed, 'length' or 'content-type' missing">
	<cfelseif http.responseHeader.Status_Code IS "422">
		<cfset response.error = "failed, didn't match checksum">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="getObject" access="public" output="false" returnType="struct" 
		description="Download an object.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="key" type="string" required="true">
	<cfargument name="file" type="string" default="">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "" }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "GET">
	<cfset arguments.url = "#this.storageUrl#/#arguments.container#/#arguments.key#">
	
	<cfif len( arguments.destination )>
		<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#"
			getAsBinary="auto"
			path="#getDirectoryFromPath( arguments.file )#"
			file="#getFileFromPath( arguments.file )#"
		>
			<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
		</cfhttp>
	<cfelse>
		<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
			<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
		</cfhttp>
	</cfif>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "202">
		<!--- Success --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif http.responseHeader.Status_Code IS "404">
		<cfset response.error = "object key '#arguments.container#/#arguments.key#' not found">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="getObjectInfo" access="public" output="false" returnType="struct" 
		description="Download an object.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="key" type="string" required="true">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "" }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "HEAD">
	<cfset arguments.url = "#this.storageUrl#/#arguments.container#/#arguments.key#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="deleteObject" access="public" output="false" returnType="struct" 
		description="Deletes an object.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="key" type="string" required="true">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "" }>
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "DELETE">
	<cfset arguments.url = "#this.storageUrl#/#arguments.container#/#arguments.key#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "202">
		<!--- Success --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif http.responseHeader.Status_Code IS "404">
		<cfset response.error = "object key '#arguments.container#' not found">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>


<cffunction name="updateObject" access="public" output="false" returnType="struct"
		description="Update an object metadata.">
	
	<cfargument name="container" type="string" required="true">
	<cfargument name="key" type="string" required="true">
	<cfargument name="metadata" type="struct" default="#{}#">
	
	<cfset var http = 0>
	<cfset var response = { success = false, error = "" }>
	<cfset var item = "">
	
	<cfif NOT this.authorized>
		<cfset authenticate()>
	</cfif>
	
	<cfset arguments.method = "POST">
	<cfset arguments.url = "#this.storageUrl#/#arguments.container#/#arguments.key#">
	
	<cfhttp result="http" method="#arguments.method#" url="#arguments.url#" charset="utf-8" timeOut="#this.httpTimeOut#">
		<cfhttpparam type="header" name="X-Auth-Token" value="#this.authToken#">
		<cfloop collection="#arguments.metadata#" item="item">
			<cfhttpparam type="header" name="X-Object-Meta-#item#" value="#arguments.metadata[ item ]#">
		</cfloop>
	</cfhttp>
	
	<!--- RESPONSE CODE ERRORS --->
	<cfif NOT isDefined( "http.responseHeader.Status_Code" )>
		<cfset response.error = "Failed, no headers returned. " & response.error>
	<cfelseif http.responseHeader.Status_Code IS "202">
		<!--- Success --->
	<cfelseif http.responseHeader.Status_Code IS "400">
		<cfset response.error = http.responseHeader.Explanation>
	<cfelseif http.responseHeader.Status_Code IS "401">
		<cfset response.error = "unauthorized">
	<cfelseif http.responseHeader.Status_Code IS "404">
		<cfset response.error = "object key '#arguments.container#/#arguments.container#' not found">
	<cfelseif listFind( "4,5", left( http.responseHeader.Status_Code, 1 ) )>
		<cfset response.error = "status code error: #http.responseHeader.Status_Code#">
	<cfelseif http.fileContent IS "Connection Timeout" OR http.fileContent IS "Connection Failure">
		<cfset response.error = http.fileContent>
	<cfelseif len( http.errorDetail )>
		<cfset response.error = http.errorDetail>
	</cfif>
	
	<cfif NOT len( response.error )>
		<cfset response.success = true>
	</cfif>
	
	<cfif this.verbose>
		<cfset response.args = arguments>
		<cfset response.http = http>
	</cfif>
	
	<cfreturn response>
</cffunction>
	

</cfcomponent>