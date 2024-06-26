# About

ETD is a collaboration between York University Libraries and Faculty of Graduate Studies to facilitate depositing of Electronic Thesis and Dissertations.

# Start developing

```
git clone https://github.com/yorkulibraries/etd.git
cd etd
docker compose up --build
```

There are 3 containers created: **web**, **db** and **mailcatcher**

# Access the front end web app in DEVELOPMENT 

http://localhost:3004/

By default, the application will listen on port 3004 and runs with RAILS_ENV=development.

To access the application in Chrome browser, you will need to add the ModHeader extension to your Chrome browser.

Header: PYORK_USER
Value: admin (or manager or whatever user you want to mimic)

For convenience, you can import the ModHeader profile from the included ModHeader_admin.json. 

# Access mailcatcher web app

http://localhost:3084/

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

Run a specific test and test within the test file.
```
docker compose exec web rt TEST=test/controllers/users_controller_test.rb

1. docker compose exec web bash
2. $>  rts TEST=test/system/students_test.rb

Note: There is option to specific test within the test file with TESTOPTS="-n '/not allow student to add committee members/'" but it may not work with 'rt' or 'rts' scripts. You will have to specify the db url and environment. 

```
#specific test with testopts does not work, then run it with rails_env and database_url as prefix.

# Access the containers

DB container
```
docker compose exec db bash
```

Webapp container
```
docker compose exec web bash
```

