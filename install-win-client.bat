@echo off

set args=0
for %%x in (%*) do set /A args+=1

set script_name=%0%

if /I %args% NEQ 3 (
  echo ERROR: arguments not matched. 
  echo You must specify "Sensu Install Directory", "Client Name", and "Local IP Address" in the right order. eg. "%script_name% c:\opt VocieIVR-1 172.16.50.209"
  goto end
)

set sensu_install_dir=%1%
:: echo %sensu_install_dir%
set sensu_client_name=%2%
:: echo %sensu_client_name%
set local_ip_address=%3%
:: echo %local_ip_address%

:: Setup Sensu Configuration
set sensu_config_dir=%sensu_install_dir%\sensu\etc\conf.d
:: echo %sensu_config_dir%
set sensu_ssl_dir=%sensu_install_dir%\sensu\etc\ssl
:: echo %sensu_ssl_dir%
set sensu_config_file=%sensu_install_dir%\sensu\bin\sensu-client.xml
:: echo %sensu_config_file%
set rabbitmq_config_file=%sensu_config_dir%\rabbitmq.json
:: echo %rabbitmq_config_file%
set client_config_file=%sensu_config_dir%\client.json
:: echo %client_config_file%

mkdir %sensu_config_dir%
mkdir %sensu_ssl_dir%

echo ^<^!-- > %sensu_config_file%
echo ^ ^ Windows^ service^ definition^ for^ Sensu >> %sensu_config_file%
echo --^> >> %sensu_config_file%
echo. >> %sensu_config_file%
echo ^<service^> >> %sensu_config_file%
echo ^ ^ ^<id^>sensu-client^<^/id^> >> %sensu_config_file%
echo ^ ^ ^<name^>Sensu Client^</name^> >> %sensu_config_file%
echo ^ ^ ^<description^>This^ service^ runs^ a^ Sensu^ client^</description^> >> %sensu_config_file%
echo ^ ^ ^<executable^>%sensu_install_dir%\sensu\embedded\bin\ruby^</executable^> >> %sensu_config_file%
echo ^ ^ ^<arguments^>%sensu_install_dir%\sensu\embedded\bin\sensu-client^ -d^ %sensu_install_dir%\sensu\etc\conf.d^ -l^ %sensu_install_dir%\sensu\sensu-client.log^</arguments^> >> %sensu_config_file%
echo ^</service^> >> %sensu_config_file%

:: Setup RabbitMQ Configuration
set _sensu_ssl_dir=%sensu_ssl_dir:\=/%
:: echo %_sensu_ssl_dir%

echo { > %rabbitmq_config_file%
echo ^ ^ "rabbitmq":^ { >> %rabbitmq_config_file%
echo ^ ^ ^ ^ "ssl":^ { >> %rabbitmq_config_file%
echo ^ ^ ^ ^ ^ ^ "cert_chain_file":^ "%_sensu_ssl_dir%/cert.pem", >> %rabbitmq_config_file%
echo ^ ^ ^ ^ ^ ^ "private_key_file":^ "%_sensu_ssl_dir%/key.pem" >> %rabbitmq_config_file%
echo ^ ^ ^ ^ }, >> %rabbitmq_config_file%
echo ^ ^ ^ ^ "host":^ "172.16.50.211", >> %rabbitmq_config_file%
echo ^ ^ ^ ^ "port":^ 5671, >> %rabbitmq_config_file%
echo ^ ^ ^ ^ "vhost":^ "/sensu", >> %rabbitmq_config_file%
echo ^ ^ ^ ^ "user":^ "sensu", >> %rabbitmq_config_file%
echo ^ ^ ^ ^ "password":^ "mypass" >> %rabbitmq_config_file%
echo ^ ^ } >> %rabbitmq_config_file%
echo } >> %rabbitmq_config_file%

:: Get Local IP Address

:: Setup Sensu Client Configuration
echo { > %client_config_file%
echo ^ ^ "client":^ { >> %client_config_file%
echo ^ ^ ^ ^ "name":^ "%sensu_client_name%", >> %client_config_file%
echo ^ ^ ^ ^ "address":^ "%local_ip_address%", >> %client_config_file%
echo ^ ^ ^ ^ "subscriptions":^ [^ "all"^ ] >> %client_config_file%
echo ^ ^ } >> %client_config_file%
echo } >> %client_config_file%

:: Setup config.yml
echo -^ %sensu_install_dir%\sensu\embedded > %sensu_install_dir%\sensu\embedded\config.yml

:: Copy SSL Certificates
copy .\ssl\cert.pem %sensu_ssl_dir%
copy .\ssl\key.pem %sensu_ssl_dir%

:: Create Windows Service Entry for Sensu Client
sc \\localhost create sensu-client start= delayed-auto binPath= %sensu_install_dir%\sensu\bin\sensu-client.exe DisplayName= "Sensu Client"

:: Start Sensu Client Service
sc start sensu-client

:end