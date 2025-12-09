import { LightningElement } from 'lwc';

export default class MyComponent extends LightningElement {
    name = 'Salesforce';

    changeName() {
        this.name = 'Lightning Web Component';
    }
}