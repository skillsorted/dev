
# B.Protocol
The BAMM (bprotocol automatic market maker)
provides automatic rebalancing over Liquity's stability pool.

it will swap your ETH with LUSD automaticly after the stabilty pool preforms a liquidation,
this will maximize your LQTY gains as the stability pool only rewards LUSD deposits

## integrating the BAMM with existing Liquity frontends and interfaces
any existing LQTY front end can integrate the BAMM into their interface to gain extra fees from the rebalancing process,
read more to learn about the verious integration options

1) integrating directly with the smart contract like [pickle.finance](https://app.pickle.finance/farms) did

2) Front-End intgration using our widgets and snipets, 
the quicker & simpler approch

## BAMM front-end integration
there are sevral ways to integrate our front-end with your exsiting front end and we will demonstrate a few options.

1) integrate our front end as a widget into an exsiting page or modal window. 
    1) in this example our widget in red border inside the original liquity app [widget example](https://integration-example.bprotocol.workers.dev/#/)

1) integrate our front-end as a page in your exsiting app. 
     1) our widget in red border as a page of the original liquity app [page example](https://integration-example.bprotocol.workers.dev/#/bprotocol)

1) integrate our front-end as a separate single page application linked to your website  
     1) click on the red B.PROTOCOL navigation link to see the SPA on the same domain using the same meta mask connection [seperate singel page application example](https://integration-example.bprotocol.workers.dev/#/farm)

### integrate our front-end as a page in your exsiting app
git clone the repo
- yarn
- cd packages/dev-frontend
- yarn
- change teh BAMM address in kovan.json & mainnet.json to your bamm version
- yarn start
- change package.json "homepage": "/<what ever path you would like the server the files from>",
- yarn build
- upload the static build to you static hosting solution and change the build folder name to the desired path

integration options
- full app: a simple relative link in your app/website to the /path you deployed to to view the full app
- a page in your app: create a page in your app that has your navigation bar using an iframe with an SRC atribute src="/directory" to display the app under your exsiting nav bar
- a widget in an already exsiting page: lastly in an already existing page add only a widget 
	- add an iframe with an src attribute to the /directory/#/widget give it the width and highet you like
	- positiion it where ever you like and you will see only the bamm widget in the iframe box

 	 




