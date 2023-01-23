import { LightningElement, api, wire } from 'lwc'
import { ShowToastEvent } from 'lightning/platformShowToastEvent'
import { getRecord, getFieldValue } from 'lightning/uiRecordApi'
import STATUS_FIELD from '@salesforce/schema/Order.Status'
import { publish, subscribe, MessageContext } from 'lightning/messageService'
import HANDLE_ORDER from '@salesforce/messageChannel/Handle_Order__c'
import getAvailableProducts from '@salesforce/apex/OrderController.getAvailableProducts'
import addToOrder from '@salesforce/apex/OrderController.addToOrder'

export default class DisplayAvailableProducts extends LightningElement {
    @api
    recordId

    errorMessage
    products = []
    allProducts = []
    selectedProducts = []
    infiniteLoadOffset = 30
    addToOrderDisabled = true
    columns = [
        { label: 'Name', fieldName: 'Name' },
        {
            label: 'Price',
            fieldName: 'UnitPrice',
            type: 'currency',
            cellAttributes: { alignment: 'left' },
        },
    ]

    // Needed for our messaging channel to message between the 2 components.
    @wire(MessageContext)
    messageContext

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [STATUS_FIELD]
    })
	order({ error, data }) {
        if (data) {
            // If our Order is Activated then its no longer able to add new products.
			if (getFieldValue(data, STATUS_FIELD) === 'Activated') {
				this.errorMessage = 'This Order is Activated and you cannot add new Order Items or confirm the Order for a second time.'
			}
        } else if (error) {
            // Proper error handling
            this.errorMessage = `Couldn't fetch the Order.`
            if (Array.isArray(error.body)) {
                this.errorMessage = error.body.map((e) => e.message).join(', ')
            } else if (typeof error.body.message === 'string') {
                this.errorMessage = error.body.message
            }
        }
	}

    @wire(getAvailableProducts)
    availableProducts({ error, data }) {
        // Get all available products.
        if (data) {
            if (!data?.length) {
                this.errorMessage = `No Products found.`
                return
            }
            this.allProducts = data
            // Push the first products in the datatable, the rest of them will be loaded using infinite-load of datatable in order to handle big amounts of products (as exercise required).
            this.products = this.allProducts.slice(0, this.infiniteLoadOffset)
        } else if (error) {
            this.errorMessage = `Couldn't fetch any Products.`
            if (Array.isArray(error.body)) {
                this.errorMessage = error.body.map((e) => e.message).join(', ')
            } else if (typeof error.body.message === 'string') {
                this.errorMessage = error.body.message
            }
        }
	}

    connectedCallback() {
        // Subscribe to the message channel to be able to receive message from the other component
        // Alternatively the 2 componenets could be wrapped in a third parent component and communicate with each other using child-parent and parent-child communication.
        // Alternatively we could also use pubsub for communication.
		subscribe(this.messageContext, HANDLE_ORDER, (message) =>
            this.handleMessage(message)
        )
    }

    handleMessage(message) {
        // We received a signal that the order is now activated therefore we must disable this LWC and show message.
        if (message.deactivate) {
            this.errorMessage = 'This Order is Activated and you cannot add new Order Items or confirm the Order for a second time.'
        }
	}

    async onAddToOrderClickHandler() {
        // When we add products to order we get all selected products of the datatable and send them to APEX to add them to the Order.
        const success = await addToOrder({
            selectedProducts: this.selectedProducts,
            orderId: this.recordId
        })
        if (success) {
            // if success then send a signal to the other component and generate an informative toast.
            publish(this.messageContext, HANDLE_ORDER, { fetch: true })
            this.showToast(
                `Success!`,
                `${this.selectedProducts.length} Product${
                    this.selectedProducts.length === 1 ? ' was' : 's were'
                } added to your Order!`,
                'success'
            )
        } else {
            // if fail generate an informative toast.
            this.showToast(
                `Error!`,
                `An error occured while adding Products to Order, please try again later!`,
                "error"
            );
        }
    }

    onLoadMoreDataHandler(event) {
        // Standard infinite load handler. If more products can be added the add them to the list of datatable otherwise stop the functionality of infinite load so it doesn't continue.
        event.target.isLoading = true
        if (this.products.length >= this.allProducts.length) {
            event.target.enableInfiniteLoading = false
        } else {
            this.products = this.products.concat(
                this.allProducts.slice(
                    this.products.length,
                    this.products.length + this.infiniteLoadOffset
                )
            )
        }
        event.target.isLoading = false
    }

    onRowSelectionHandler(event) {
        // If products were selected or unselected then update our variable
        this.selectedProducts = event.detail.selectedRows
        this.addToOrderDisabled = !event.detail.selectedRows.length
    }

    showToast(title, message, variant) {
        // Reusable show toast
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant,
            })
        )
    }
}