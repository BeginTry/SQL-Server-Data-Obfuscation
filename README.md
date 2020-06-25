# SQL Server Data Obfuscation
This series of stored procedures uses SQL Server's built-in Machine Learning services and the R language for both generating data sets of fake data, and for obfuscating existing SQL Server data with fake data.

Additional details and examples are available in this blog post: <a target="_blank" href="https://itsalljustelectrons.blogspot.com/2020/06/Data-Obfuscation-for-SQL-Server.html">Data Obfuscation for SQL Server</a>

<h3>Example - Full Names</h3>
<p>
<pre>
EXEC MLtools.Obfuscator.SetFullNameParts
	@DatabaseName = 'Adventureworks',
	@TableSchema = 'Person',
	@TableName = 'Person',
	@FirstNameColumn = 'FirstName',
	@LastNameColumn = 'LastName',
	@MiddleNameColumn = 'MiddleName',
	@DisableTriggers = 1;
</pre>

<img alt="Obfuscator.SetFullNames - Data Obfuscation for SQL Server" border="0" src="https://3.bp.blogspot.com/-bSDtsWESySI/XubWqXNFAGI/AAAAAAAAHMg/KQfW4vw-DW8iDnGbhyzOUiWKdytIRnaKACNcBGAsYHQ/s1600/itsalljustelectrons.blogspot.com%2B-%2BSQL%2BServer%2BData%2BObfuscation%2B-%2BFull%2BNames%2B01.png" />
</p>

<p>
<table>
<tr><th>Before</th><th>After</th></tr>
<tr><td>
<img alt="Obfuscator.SetFullNames - Data Obfuscation for SQL Server" border="0" src="https://3.bp.blogspot.com/-vQrs3peCdlc/XubWtZclaII/AAAAAAAAHMk/Kee9Ykni94A9WhgZmxi8Y7AxQWoqXnY1ACNcBGAsYHQ/s1600/itsalljustelectrons.blogspot.com%2B-%2BSQL%2BServer%2BData%2BObfuscation%2B-%2BFull%2BNames%2B02.png" />
</td>
<td>
<img alt="Obfuscator.SetFullNames - Data Obfuscation for SQL Server" border="0" src="https://1.bp.blogspot.com/-ak1U9W_9sSI/XubWwceSYGI/AAAAAAAAHMs/SOu-5iFqxGYsRv7VfbCx1aezZyUTybddwCNcBGAsYHQ/s1600/itsalljustelectrons.blogspot.com%2B-%2BSQL%2BServer%2BData%2BObfuscation%2B-%2BFull%2BNames%2B03.png" />
</td>
</tr>
</table>
</p>
