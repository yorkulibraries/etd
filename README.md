# etd

# Start developing

```
git clone https://github.com/yorkulibraries/etd.git
cd etd
docker compose up --build
```

There are 2 containers created: *etd-web-1* and *etd-db-1*

# Access the front end web app in DEVELOPMENT 

By default, the application will listen on port 4004 and runs with RAILS_ENV=development.

To access the application in Chrome browser, you will need to add the ModHeader extension to your Chrome browser.

Once the extension has been activated, you can add the following header to the site http://localhost:4004/. This will enable you to login as **admin** user.

Header: PYORK_USER

Value: admin

The application is now accessible at http://localhost:4004/

# What if I want to use a different port?

If you wish to use a different port, you can set the PORT environment 

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

