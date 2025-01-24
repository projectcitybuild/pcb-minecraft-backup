default: image

.PHONY: image
image:
	docker build -t pcb-minecraft-backup .

.PHONY: run
run: image
	docker run -it pcb-minecraft-backup

.PHONY: start
start:
	docker run -v $(pwd):/app pcb-minecraft-backup npm start

.PHONY: install
install: image
    docker run -v $(pwd):/app pcb-minecraft-backup npm install