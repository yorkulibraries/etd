# etd

# Start developing

```
git clone https://github.com/yorkulibraries/etd.git
cd etd
docker compose up --build
```

There are 2 containers created: *etd-web-1* and *etd-db-1*

# Access the front end web app in DEVELOPMENT 

By default, the application will listen on port 3004 and runs with RAILS_ENV=development.

To access the application in Chrome browser, you will need to add the ModHeader extension to your Chrome browser.

Header: PYORK_USER
Value: admin (or manager or whatever user you want to mimic)

For convenience, you can import the ModHeader profile from the included ModHeader_admin.json. 


# What if I want to use a different port?

If you wish to use a different port, you can set the PORT environment or change PORT in .env file.

```
PORT=4005 docker compose up --build
```

# Run tests

Start the containers if you haven't started them yet.

```
docker compose up --build
```

Run all the tests

```
docker compose exec web rt 
```

Run a specific test
```
docker compose exec web rt test/controllers/users_controller_test.rb
```

# Access the containers

DB container
```
docker compose exec db bash
```

Webapp container
```
docker compose exec web bash
```

