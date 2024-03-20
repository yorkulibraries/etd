# etd

# Start developing

```
git clone https://github.com/yorkulibraries/etd.git
cd etd
docker compose up --build
```

There are 2 containers created: *etd-app-1* and *etd-mysql-1*

# Access the front end web app in DEVELOPMENT 
To access the application in Chrome browser, you will need to add the ModHeader extension to your Chrome browser.

Once the extension has been activated, you can add the following header to the site http://localhost:4004/. This will enable you to login as **admin** user.

Header: PYORK_USER

Value: admin

The application is now accessible at http://localhost:4004/


# Access the containers

Mysql container
```
docker exec -it etd-mysql-1 bash
```

ETD app container
```
docker exec -it etd-app-1 bash
```
