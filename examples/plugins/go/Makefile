name=plugin_go

$(name).so: main.go mist_helper.go
	go build -o $(name).so -buildmode=c-shared main.go mist_helper.go
	# TODO: can we prevent header creation with build flags?
	rm $(name).h
