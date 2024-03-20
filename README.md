# etd

# Start developing

```
git clone https://github.com/yorkulibraries/etd.git
cd etd
docker compose up --build
```

There are 2 containers created: *etd-app-1* and *etd-mysql-1*

The application should be at http://localhost:4004/

# Access the containers

Mysql container
```
docker exec -it etd-mysql-1 bash
```

ETD app container
```
docker exec -it etd-app-1 bash
```
