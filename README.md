# emqx_bridge_nats: Plugin for Nats
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fiotblue-kuido%2Femqx-bridge-nats.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fiotblue-kuido%2Femqx-bridge-nats?ref=badge_shield)


## Introduction
This plugin is to bridge data to NATS message bus.

## NATS
NATS is an open source, lightweight, high-performance distributed messaging middleware that implements high scalability and an elegant Publish/Subscribe model and is developed in Golang.
NATS messaging supports the exchange of data segmented into messages between computer applications and services. These messages are resolved by topic and do not depend on network location. This provides an abstraction layer between the application or service and the underlying physical network. The data is encoded and formed into a message and sent by the publisher. The message is received, decoded and processed by one or more subscribers.
### 测试环境
```sh
docker run --name nats --rm -p 4222:4222 -p 8222:8222 nats
``` 

## Configuration
```ini
##====================================================================
## Configuration for EMQ X NATS Broker Bridge
##====================================================================

## Bridge address: node address for bridge.
##
## Value: String
## Example: 127.0.0.1
bridge.nats.address = 127.0.0.1

## Bridge Port: node port for bridge.
##
## Value: Integer
## Value: Port
bridge.nats.port = 4222

```
## Subscription test
Let's write a simple golang client to implement subscription:

```go
package main

import (
	"fmt"

	"github.com/nats-io/nats.go"
)

func main() {
	nc, err := nats.Connect("nats://127.0.0.1:4222")
	if err != nil {
		fmt.Println(err.Error())
		return
	}
	nc.Subscribe("iotpaas.devices.message", func(m *nats.Msg) {
		fmt.Printf("message: %s\n", string(m.Data))
	})
	nc.Subscribe("iotpaas.devices.connected", func(m *nats.Msg) {
		fmt.Printf("connect: %s\n", string(m.Data))
	})
	nc.Subscribe("iotpaas.devices.disconnected", func(m *nats.Msg) {
		fmt.Printf("disconnect: %s\n", string(m.Data))
	})

	for {
	}

}

```

## Output
```
disconnect: {"action":"disconnected","clientid":"mqttjs_661dd06d29","reasonCode":"remote"}
connect: {"action":"connected","clientid":"mqttjs_661dd06d29"}
message: {"id":1902572155295492,"qos":0,"clientid":"mqttjs_661dd06d29","topic":"testtopic","payload":"{ \"msg\": \"Hello, World!\" }"}
```

## License
[![FOSSA Status](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fiotblue-kuido%2Femqx-bridge-nats.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fiotblue-kuido%2Femqx-bridge-nats?ref=badge_large)