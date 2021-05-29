<?php
header("Content-Type: application/json");
if($_SERVER["REQUEST_METHOD"]=="POST"){
	if(isset($_SERVER["CONTENT_TYPE"])&&$_SERVER["CONTENT_TYPE"]=="application/json")
		//$_POST=json_decode(file_get_contents('php://input'), true);
		$mail=file_get_contents('php://input');
		file_put_contents("./mail.txt", $mail."\n",FILE_APPEND);
	echo '{"status":"success"}';
}